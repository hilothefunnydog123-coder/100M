import 'dart:async';

import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

import 'fakes.dart' show draftRequest;
import 'support/harness.dart';
import 'support/test_db.dart';

void main() {
  withDb((testDb) {
    late Harness h;
    late SignIn dana;

    Future<void> useHarness(Harness harness) async {
      h = harness;
      dana = await h.owner('dana@example.com');
    }

    setUp(() => useHarness(Harness(testDb())));

    Future<Map<String, Object?>> plan() async =>
        (await h.accounts.me(dana.account))['business']!
            as Map<String, Object?>;

    Future<int> used() async =>
        ((await plan())['plan']! as Map)['trial_drafts_used']! as int;

    test('drafts and meters the trial', () async {
      final draft = await h.app.drafts.create(dana.account, draftRequest());
      expect((draft['draft']! as Map)['items'], isNotEmpty);
      expect(draft['model'], 'claude-opus-5-5');
      expect(await used(), 1);
      final row = (await h.db.one('SELECT * FROM drafts'))!;
      expect(row['state'], 'done');
      expect(row['usable'], isTrue);
      expect(row['photos'], 2);
      expect(row['input_tokens'], 9000);
      expect(row['cost_micros'], greaterThan(0));
      expect(
        h.app.metrics.render(),
        contains('jobwalk_drafts_total{outcome="ok"} 1'),
      );
    });

    test('unusable and failed drafts do not use the trial', () async {
      h.drafter.behavior = (r) async => Draft(
        const AiDraft(
          photosUsable: false,
          retakeAdvice: 'These photos show a cat.',
        ),
        DraftStats(),
        model: 'claude-opus-5-5',
      );
      await h.app.drafts.create(dana.account, draftRequest());
      expect(await used(), 0);

      h.drafter.behavior = (r) async =>
          throw DraftFailed('bad output', cause: const FormatException());
      final e = await apiError(
        () => h.app.drafts.create(dana.account, draftRequest()),
      );
      expect(e.status, 502);
      expect(await used(), 0);
      expect(
        (await h.db.query(
          'SELECT state FROM drafts ORDER BY id',
        )).map((r) => r['state']),
        ['done', 'failed'],
      );
    });

    test('an exhausted trial asks for an upgrade', () async {
      await useHarness(Harness(testDb(), config: testConfig(trialDrafts: 2)));
      await h.app.drafts.create(dana.account, draftRequest());
      await h.app.drafts.create(dana.account, draftRequest());
      final e = await apiError(
        () => h.app.drafts.create(dana.account, draftRequest()),
      );
      expect(e.status, 402);
      expect(e.code, 'upgrade_required');
      expect(h.drafter.calls, 2);

      await h.db.execute(
        "UPDATE businesses SET plan = 'pro', plan_status = 'active'",
      );
      await h.app.drafts.create(dana.account, draftRequest());
      expect(h.drafter.calls, 3);
    });

    test('paid plans have a fair-use ceiling', () async {
      await useHarness(
        Harness(testDb(), config: testConfig(monthlyDraftCap: 2)),
      );
      await h.db.execute(
        "UPDATE businesses SET plan = 'pro', plan_status = 'active'",
      );
      await h.app.drafts.create(dana.account, draftRequest());
      await h.app.drafts.create(dana.account, draftRequest());
      final e = await apiError(
        () => h.app.drafts.create(dana.account, draftRequest()),
      );
      expect(e.code, 'usage_limit');
      h.advance(const Duration(days: 31));
      await h.app.drafts.create(dana.account, draftRequest());
    });

    test('a retry with the same key replays the draft for free', () async {
      final first = await h.app.drafts.create(
        dana.account,
        draftRequest(),
        idempotencyKey: 'draft-key-0001',
      );
      final again = await h.app.drafts.create(
        dana.account,
        draftRequest(),
        idempotencyKey: 'draft-key-0001',
      );
      expect(h.drafter.calls, 1);
      expect(again['replayed'], isTrue);
      expect(again['draft'], first['draft']);
      expect(await used(), 1);

      // Keys are per business.
      final sam = await h.owner('sam@example.com');
      await h.app.drafts.create(
        sam.account,
        draftRequest(),
        idempotencyKey: 'draft-key-0001',
      );
      expect(h.drafter.calls, 2);
    });

    test('a key still in flight answers 409; a failed one can retry', () async {
      final gate = Completer<void>();
      h.drafter.behavior = (r) async {
        await gate.future;
        return Draft(SampleJob.livingRoom.draft, DraftStats());
      };
      final running = h.app.drafts.create(
        dana.account,
        draftRequest(),
        idempotencyKey: 'draft-key-0002',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final e = await apiError(
        () => h.app.drafts.create(
          dana.account,
          draftRequest(),
          idempotencyKey: 'draft-key-0002',
        ),
      );
      expect(e.code, 'in_progress');
      gate.complete();
      await running;

      h.drafter.behavior = (r) async => throw DraftFailed('boom');
      await apiError(
        () => h.app.drafts.create(
          dana.account,
          draftRequest(),
          idempotencyKey: 'draft-key-0003',
        ),
      );
      h.drafter.behavior = null;
      final retried = await h.app.drafts.create(
        dana.account,
        draftRequest(),
        idempotencyKey: 'draft-key-0003',
      );
      expect(retried['replayed'], isNull);
    });

    test('maps model failures to clear errors', () async {
      Future<ApiError> failWith(Object error) {
        h.drafter.behavior = (r) async => throw error;
        return apiError(
          () => h.app.drafts.create(dana.account, draftRequest()),
        );
      }

      expect((await failWith(DraftFailed('no', refused: true))).status, 422);
      final busy = await failWith(
        DraftFailed(
          'overloaded',
          cause: ClaudeApiException(529, 'overloaded_error', 'Overloaded'),
        ),
      );
      expect(busy.status, 503);
      expect(busy.retryAfter, isNotNull);
      expect((await failWith(const Overloaded())).status, 503);
      expect((await failWith(StateError('?'))).status, 502);

      h.drafter.behavior = (r) async {
        await Future<void>.delayed(const Duration(seconds: 10));
        return Draft(SampleJob.livingRoom.draft, DraftStats());
      };
      final timeout = await apiError(
        () => h.app.drafts.create(dana.account, draftRequest()),
      );
      expect(timeout.status, 504);
      expect(await used(), 0);
    });

    test('a phone that lost the connection can ask how it went', () async {
      final gate = Completer<void>();
      h.drafter.behavior = (r) async {
        await gate.future;
        return Draft(SampleJob.livingRoom.draft, DraftStats());
      };
      final running = h.app.drafts.create(
        dana.account,
        draftRequest(),
        idempotencyKey: 'draft-key-0100',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await h.app.drafts.status(dana.account, 'draft-key-0100'), {
        'state': 'running',
      });
      gate.complete();
      await running;
      final done = await h.app.drafts.status(dana.account, 'draft-key-0100');
      expect(done['state'], 'done');
      expect((done['draft']! as Map)['items'], isNotEmpty);

      expect(
        (await apiError(
          () => h.app.drafts.status(dana.account, 'draft-key-9999'),
        )).status,
        404,
      );
      final sam = await h.owner('sam@example.com');
      expect(
        (await apiError(
          () => h.app.drafts.status(sam.account, 'draft-key-0100'),
        )).status,
        404,
        reason: 'keys are per business',
      );
    });

    test('a draft abandoned by a restart reads as failed', () async {
      await h.db.execute(
        'INSERT INTO drafts (business_id, idempotency_key, state, created_at) '
        "VALUES (@b, 'draft-key-0200', 'running', @at:timestamptz)",
        {
          'b': dana.account.businessId,
          'at': h.now.subtract(const Duration(minutes: 30)),
        },
      );
      expect(await h.app.drafts.status(dana.account, 'draft-key-0200'), {
        'state': 'failed',
      });
      // Retrying the same key takes it over.
      final draft = await h.app.drafts.create(
        dana.account,
        draftRequest(),
        idempotencyKey: 'draft-key-0200',
      );
      expect(draft['draft'], isNotNull);
    });

    test('rejects bad idempotency keys', () async {
      final e = await apiError(
        () => h.app.drafts.create(
          dana.account,
          draftRequest(),
          idempotencyKey: 'no spaces allowed',
        ),
      );
      expect(e.code, 'invalid_idempotency_key');
    });
  });
}
