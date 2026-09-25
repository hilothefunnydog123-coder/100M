import 'dart:async';

import 'package:jobwalk_core/jobwalk_core.dart';

import '../claude_client.dart';
import '../common.dart';
import '../db/database.dart';
import '../drafter.dart';
import '../limits.dart';
import 'accounts.dart';
import 'plans.dart';

/// What a finished draft cost, for metrics.
typedef DraftOutcome = ({String outcome, double costUsd, int ms});

/// AI drafts with metering, plan limits, and safe retries.
///
/// A phone that times out and retries with the same `Idempotency-Key`
/// gets the first draft back instead of paying for a second one.
class DraftService {
  DraftService({
    required Db db,
    required QuoteDrafter drafter,
    required ConcurrencyLimiter concurrency,
    required Limiter perBusiness,
    this.plans = const PlanRules(),
    this.timeout = const Duration(seconds: 170),
    Clock clock = systemClock,
    LogSink? log,
    void Function(DraftOutcome)? onDraft,
  }) : _db = db,
       _drafter = drafter,
       _concurrency = concurrency,
       _perBusiness = perBusiness,
       _clock = clock,
       _log = log ?? ((_) {}),
       _onDraft = onDraft ?? ((_) {});

  final PlanRules plans;
  final Duration timeout;
  final Db _db;
  final QuoteDrafter _drafter;
  final ConcurrencyLimiter _concurrency;
  final Limiter _perBusiness;
  final Clock _clock;
  final LogSink _log;
  final void Function(DraftOutcome) _onDraft;

  static final _keyPattern = RegExp(r'^[A-Za-z0-9_.:-]{8,100}$');

  Future<Map<String, Object?>> create(
    Account a,
    DraftRequest request, {
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey?.trim();
    if (key != null && key.isNotEmpty && !_keyPattern.hasMatch(key)) {
      throw ApiError.badRequest(
        'invalid_idempotency_key',
        'Idempotency-Key must be 8-100 letters, digits, or ._:-',
      );
    }
    final useKey = key == null || key.isEmpty ? null : key;

    // A retry of a finished draft returns it without spending anything.
    if (useKey != null) {
      final replay = await _replay(a, useKey);
      if (replay != null) return replay;
    }

    final wait = await _perBusiness.acquire('drafts:${a.businessId}');
    if (wait != null) {
      throw ApiError.rateLimited(
        wait,
        "You've drafted several quotes in a short time. Try again in a few "
        'minutes.',
      );
    }

    final plan = await _plan(a.businessId);
    if (plan.paid) {
      final recent =
          (await _db.one(
                '''
        SELECT count(*)::int AS n FROM drafts
        WHERE business_id = @b AND usable AND created_at > @since:timestamptz''',
                {
                  'b': a.businessId,
                  'since': _clock().subtract(const Duration(days: 30)),
                },
              ))!['n']
              as int;
      if (recent >= plans.monthlyDraftCap) {
        throw ApiError(
          429,
          'usage_limit',
          "You've made ${plans.monthlyDraftCap} AI drafts in 30 days, the "
              'fair-use limit. Write us and we will raise it.',
        );
      }
    } else if (!await _takeTrialDraft(a.businessId)) {
      throw ApiError(
        402,
        'upgrade_required',
        "You've used your ${plans.trialDrafts} free AI drafts. Upgrade to "
            'keep drafting quotes from photos.',
      );
    }

    final draftId = await _start(a, useKey, request.photos.length);
    if (draftId == null) {
      // Lost a race with a concurrent retry of the same key.
      if (!plan.paid) await _refundTrialDraft(a.businessId);
      return await _replay(a, useKey!) ??
          (throw ApiError(
            409,
            'in_progress',
            'This draft is still being made. Try again in a moment.',
          ));
    }

    final watch = Stopwatch()..start();
    try {
      final draft = await _concurrency
          .run(() => _drafter.draft(request, userId: a.businessId))
          .timeout(timeout);
      final response = draft.toJson();
      final usable = draft.draft.isUsable;
      final cost = draft.stats.estimatedCostUsd ?? 0;
      await _db.execute(
        '''
        UPDATE drafts SET state = 'done', response = @r:jsonb, usable = @u,
          model = @m, input_tokens = @in:int4, output_tokens = @out:int4,
          cost_micros = @c:int8, latency_ms = @ms:int4,
          finished_at = @now:timestamptz
        WHERE id = @id:int8''',
        {
          'r': response,
          'u': usable,
          'm': draft.model,
          'in':
              draft.stats.inputTokens +
              draft.stats.cacheReadTokens +
              draft.stats.cacheWriteTokens,
          'out': draft.stats.outputTokens,
          'c': (cost * 1e6).round(),
          'ms': watch.elapsedMilliseconds,
          'now': _clock(),
          'id': draftId,
        },
      );
      // Drafts that can't be quoted (wrong photos) don't use up the trial.
      if (!usable && !plan.paid) await _refundTrialDraft(a.businessId);
      _log({
        'event': 'draft',
        'business': a.businessId,
        'usable': usable,
        'lines': draft.draft.items.length,
        'tiers': draft.draft.tiers.length,
        'photos': request.photos.length,
        'trade': request.profile.primaryTrade.id,
        'ms': watch.elapsedMilliseconds,
        ...draft.stats.toJson(),
      });
      _onDraft((
        outcome: usable ? 'ok' : 'unusable',
        costUsd: cost,
        ms: watch.elapsedMilliseconds,
      ));
      return response;
    } on Object catch (e) {
      await _db.execute(
        '''
        UPDATE drafts SET state = 'failed', latency_ms = @ms:int4,
          finished_at = @now:timestamptz
        WHERE id = @id:int8''',
        {'ms': watch.elapsedMilliseconds, 'now': _clock(), 'id': draftId},
      );
      if (!plan.paid) await _refundTrialDraft(a.businessId);
      final error = _toApiError(e, watch.elapsedMilliseconds);
      _onDraft((
        outcome: error.code,
        costUsd: 0,
        ms: watch.elapsedMilliseconds,
      ));
      throw error;
    }
  }

  Future<BusinessPlan> _plan(String businessId) async => BusinessPlan.fromRow(
    (await _db.one(
      'SELECT plan, plan_status, trial_drafts_used FROM businesses '
      'WHERE id = @b',
      {'b': businessId},
    ))!,
    plans,
  );

  /// Reserves one trial draft, atomically, so parallel drafts can't
  /// overspend it.
  Future<bool> _takeTrialDraft(String businessId) async =>
      await _db.execute(
        '''
        UPDATE businesses SET trial_drafts_used = trial_drafts_used + 1
        WHERE id = @b AND trial_drafts_used < @max:int4''',
        {'b': businessId, 'max': plans.trialDrafts},
      ) ==
      1;

  Future<void> _refundTrialDraft(String businessId) => _db.execute(
    '''
    UPDATE businesses SET trial_drafts_used = GREATEST(0, trial_drafts_used - 1)
    WHERE id = @b''',
    {'b': businessId},
  );

  /// Records the attempt. Returns null when another request holds [key].
  Future<int?> _start(Account a, String? key, int photos) async {
    final params = {
      'b': a.businessId,
      'u': a.userId,
      'k': key,
      'p': photos,
      'now': _clock(),
    };
    final inserted = await _db.one('''
      INSERT INTO drafts (business_id, user_id, idempotency_key, photos,
        created_at)
      VALUES (@b, @u, @k, @p:int4, @now:timestamptz)
      ON CONFLICT (business_id, idempotency_key)
        WHERE idempotency_key IS NOT NULL DO NOTHING
      RETURNING id''', params);
    if (inserted != null) return inserted['id'] as int;
    // A failed or abandoned attempt with this key may be retried.
    final retried = await _db.one(
      '''
      UPDATE drafts SET state = 'running', user_id = @u, photos = @p:int4,
        created_at = @now:timestamptz, finished_at = NULL
      WHERE business_id = @b AND idempotency_key = @k
        AND (state = 'failed' OR (state = 'running' AND created_at < @stale:timestamptz))
      RETURNING id''',
      {...params, 'stale': _clock().subtract(timeout * 2)},
    );
    return retried?['id'] as int?;
  }

  Future<Map<String, Object?>?> _replay(Account a, String key) async {
    final row = await _db.one(
      'SELECT state, response FROM drafts '
      'WHERE business_id = @b AND idempotency_key = @k',
      {'b': a.businessId, 'k': key},
    );
    if (row == null || row['state'] != 'done' || row['response'] == null) {
      return null;
    }
    return {...asMap(row['response']), 'replayed': true};
  }

  ApiError _toApiError(Object e, int ms) {
    switch (e) {
      case Overloaded():
        _log({'event': 'overloaded', 'queued': _concurrency.queued});
        return _busy();
      case TimeoutException():
        _log({'event': 'draft_timeout', 'ms': ms});
        return ApiError(504, 'timeout', 'The draft took too long. Try again.');
      case DraftFailed(:final refused, :final cause):
        _log({
          'event': 'draft_failed',
          'refused': refused,
          'cause': cause is ClaudeApiException
              ? '${cause.statusCode} ${cause.type} ${cause.requestId ?? ''}'
              : '${cause?.runtimeType}',
          'ms': ms,
        });
        if (refused) {
          return ApiError(
            422,
            'refused',
            "We can't draft a quote from these photos. Try photos of the job "
                'itself.',
          );
        }
        if (cause is ClaudeApiException && cause.isTransient) return _busy();
        return ApiError(
          502,
          'draft_failed',
          "We couldn't finish this draft. Please try again.",
        );
      default:
        _log({'event': 'draft_error', 'error': '$e', 'ms': ms});
        return ApiError(
          502,
          'draft_failed',
          "We couldn't finish this draft. Please try again.",
        );
    }
  }

  static ApiError _busy() => ApiError(
    503,
    'busy',
    'Jobwalk is very busy right now. Please try again in a minute.',
    retryAfter: const Duration(seconds: 30),
  );
}
