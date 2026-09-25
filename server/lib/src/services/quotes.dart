import 'dart:convert';

import 'package:jobwalk_core/jobwalk_core.dart';

import '../common.dart';
import '../db/database.dart';
import 'accounts.dart';
import 'outbox.dart';

/// A published quote as the customer page shows it.
class CustomerView {
  const CustomerView({
    required this.publicId,
    required this.businessId,
    required this.quoteId,
    required this.revision,
    required this.quote,
    required this.response,
    this.onlineDeposit = false,
    this.depositPaidCents,
    this.depositPaidAt,
  });

  final String publicId;
  final String businessId;
  final String quoteId;
  final int revision;
  final PublicQuote quote;
  final CustomerResponse response;

  /// The contractor takes card deposits through Jobwalk.
  final bool onlineDeposit;
  final int? depositPaidCents;
  final DateTime? depositPaidAt;

  bool get approved => response.approvedAt != null;
  bool get depositPaid => depositPaidAt != null;

  /// The option the customer approved.
  PublicOption? get approvedOption => approved
      ? (quote.option(response.approvedTierId) ?? quote.defaultOption)
      : null;

  /// Show "Pay the deposit" on the page.
  bool get canPayDeposit =>
      onlineDeposit && !depositPaid && (approvedOption?.depositCents ?? 0) > 0;
}

enum ApproveOutcome {
  approved,
  alreadyApproved,
  expired,
  missing,
  option,
  name,
  agree,
}

/// Quotes synced from phones, the links customers open, and what they do
/// there.
class QuoteService {
  QuoteService({
    required Db db,
    required Outbox outbox,
    required this.publicUrl,
    this.onlineDeposits = false,
    this.followUpAfter = const Duration(days: 3),
    Clock clock = systemClock,
    LogSink? log,
  }) : _db = db,
       _outbox = outbox,
       _clock = clock,
       _log = log ?? ((_) {});

  /// Origin for customer links, e.g. `https://jobwalk.app`.
  final Uri publicUrl;

  /// Card deposits are configured on this server (Stripe Connect).
  final bool onlineDeposits;

  /// When to nudge the contractor about a quote with no decision.
  final Duration followUpAfter;

  final Db _db;
  final Outbox _outbox;
  final Clock _clock;
  final LogSink _log;

  static final idPattern = RegExp(r'^[A-Za-z0-9_-]{4,64}$');
  static final publicIdPattern = RegExp(r'^[a-z0-9]{12,32}$');

  String customerUrl(String publicId) =>
      publicUrl.replace(path: '/q/$publicId').toString();

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------

  static const _select = '''
    SELECT q.id, q.version, q.deleted, q.data, q.seq, q.status,
      p.public_id, p.revision, p.response, p.sent_at, p.deposit_status,
      p.deposit_paid_cents, p.deposit_paid_at
    FROM quotes q
    LEFT JOIN publications p ON p.business_id = q.business_id AND p.quote_id = q.id''';

  /// Quotes changed after [since], oldest change first. Pass the returned
  /// cursor back to get the next page; `more` says whether to ask again.
  Future<Map<String, Object?>> changes(
    Account a, {
    int since = 0,
    int limit = 100,
  }) async {
    final n = limit.clamp(1, 500);
    final rows = await _db.query(
      '$_select WHERE q.business_id = @b AND q.seq > @since:int8 '
      'ORDER BY q.seq LIMIT @n:int4',
      {'b': a.businessId, 'since': since, 'n': n},
    );
    return {
      'items': [for (final r in rows) _present(r)],
      'cursor': rows.isEmpty ? since : rows.last['seq'],
      'more': rows.length == n,
    };
  }

  Future<Map<String, Object?>> get(Account a, String id) async {
    final row = await _load(_db, a.businessId, id);
    if (row == null || row['deleted'] == true) throw _missing();
    return _present(row);
  }

  /// Creates or updates a quote. [body] is `{quote, base_version}`, where
  /// base_version is the version the phone last saw (0 for a new quote).
  /// A stale base_version gets 409 with the server's copy to merge.
  Future<Map<String, Object?>> put(
    Account a,
    String id,
    Map<String, Object?> body,
  ) async {
    if (!idPattern.hasMatch(id)) throw _missing();
    final parsed = Quote.fromJson(body['quote']);
    if (parsed == null || parsed.id != id) {
      throw ApiError.badRequest(
        'invalid_quote',
        'The quote needs an id matching the URL and a created date.',
      );
    }
    final base = asInt(body['base_version']) ?? 0;
    final data = _storable(parsed);

    return _db.tx((tx) async {
      await _lock(tx, a.businessId);
      final now = _clock();
      final row = await _load(tx, a.businessId, id);
      if (row == null) {
        await tx.execute(
          '''
          INSERT INTO quotes (business_id, id, number, status, data, version,
            seq, created_at, updated_at)
          VALUES (@b, @id, @n:int4, @s, @d:jsonb, 1, nextval('sync_seq'),
            @now:timestamptz, @now:timestamptz)''',
          {
            'b': a.businessId,
            'id': id,
            'n': parsed.number,
            's': parsed.status.id,
            'd': data,
            'now': now,
          },
        );
        _log({'event': 'quote_created', 'business': a.businessId});
        return _present((await _load(tx, a.businessId, id))!);
      }
      if (row['deleted'] == true) {
        throw ApiError(
          409,
          'deleted',
          'This quote was deleted on another device.',
          details: {'current': _present(row)},
        );
      }
      // A retry of a write that already landed: same content, no conflict.
      if (_jsonEquals(row['data'], data)) return _present(row);
      if (row['version'] != base) {
        throw ApiError(
          409,
          'conflict',
          'This quote was changed on another device.',
          details: {'current': _present(row)},
        );
      }
      final status = _effective(parsed, row).status;
      await tx.execute(
        '''
        UPDATE quotes SET data = @d:jsonb, number = @n:int4, status = @s,
          version = version + 1, seq = nextval('sync_seq'),
          updated_at = @now:timestamptz
        WHERE business_id = @b AND id = @id''',
        {
          'd': data,
          'n': parsed.number,
          's': status.id,
          'now': now,
          'b': a.businessId,
          'id': id,
        },
      );
      return _present((await _load(tx, a.businessId, id))!);
    });
  }

  /// Deletes a quote everywhere: phones get a tombstone, the customer link
  /// stops working, and its photos are removed.
  Future<Map<String, Object?>> delete(Account a, String id) async {
    if (!idPattern.hasMatch(id)) throw _missing();
    return _db.tx((tx) async {
      await _lock(tx, a.businessId);
      final row = await _load(tx, a.businessId, id);
      if (row == null) throw _missing();
      if (row['deleted'] == true) return _present(row);
      final photoIds = Quote.fromJson(row['data'])?.photoKeys ?? const [];
      if (photoIds.isNotEmpty) {
        final photos = await tx.query(
          'DELETE FROM photos WHERE business_id = @b AND id = ANY(@ids:_text) '
          'RETURNING object_key',
          {'b': a.businessId, 'ids': photoIds},
        );
        if (photos.isNotEmpty) {
          await _outbox.add(tx, 'storage.delete', {
            'keys': [for (final p in photos) p['object_key']],
          });
        }
      }
      await tx.execute(
        'DELETE FROM publications WHERE business_id = @b AND quote_id = @id',
        {'b': a.businessId, 'id': id},
      );
      await tx.execute(
        '''
        UPDATE quotes SET deleted = true, data = '{}', status = 'deleted',
          version = version + 1, seq = nextval('sync_seq'),
          updated_at = @now:timestamptz
        WHERE business_id = @b AND id = @id''',
        {'now': _clock(), 'b': a.businessId, 'id': id},
      );
      _log({'event': 'quote_deleted', 'business': a.businessId});
      return _present((await _load(tx, a.businessId, id))!);
    });
  }

  // ---------------------------------------------------------------------------
  // Publishing
  // ---------------------------------------------------------------------------

  /// Puts the stored quote at its customer link. The page is built here
  /// from the synced quote and the business profile, so it always matches
  /// what the contractor sees. Unchanged quotes keep their revision.
  Future<Map<String, Object?>> publish(Account a, String id) async {
    if (!idPattern.hasMatch(id)) throw _missing();
    return _db.tx((tx) async {
      await _lock(tx, a.businessId);
      final row = await _load(tx, a.businessId, id);
      if (row == null || row['deleted'] == true) throw _missing();
      final business = (await tx.one(
        'SELECT profile FROM businesses WHERE id = @b',
        {'b': a.businessId},
      ))!;
      final profile = BusinessProfile.fromJson(business['profile']);
      if (profile.name.isEmpty) {
        throw ApiError.badRequest(
          'profile_incomplete',
          'Add your business name in settings before sending quotes.',
        );
      }
      final quote = Quote.fromJson(row['data'])!;
      final now = _clock();
      final content = PublicQuote.fromQuote(quote, profile, issuedAt: now);
      final problem = content.validate();
      if (problem != null) {
        throw ApiError.badRequest('invalid_quote', problem);
      }
      final hash = _contentHash(content);
      var publicId = row['public_id'] as String?;
      int revision;
      if (publicId == null) {
        publicId = randomSlug(16);
        revision = 1;
        await tx.execute(
          '''
          INSERT INTO publications (public_id, business_id, quote_id,
            published_by, revision, content, content_hash, response, sent_at,
            created_at, updated_at)
          VALUES (@p, @b, @q, @u, 1, @c:jsonb, @h, '{}', @now:timestamptz,
            @now:timestamptz, @now:timestamptz)''',
          {
            'p': publicId,
            'b': a.businessId,
            'q': id,
            'u': a.userId,
            'c': content.toJson(),
            'h': hash,
            'now': now,
          },
        );
        await _event(tx, a.businessId, id, publicId, 'sent', {
          'revision': 1,
          'total_cents': content.defaultOption.totalCents,
          'options': content.options.length,
        });
      } else {
        final response = CustomerResponse.fromJson(row['response']);
        if (response.approvedAt != null) {
          throw ApiError(
            409,
            'already_approved',
            'The customer already approved this quote. Duplicate it to send '
                'changes.',
          );
        }
        final pub = (await tx.one(
          'SELECT content, content_hash FROM publications WHERE public_id = @p',
          {'p': publicId},
        ))!;
        final current = PublicQuote.fromJson(pub['content']);
        if (pub['content_hash'] == hash && now.isBefore(current.validUntil)) {
          return {..._present(row), 'changed': false};
        }
        revision = (row['revision'] as int) + 1;
        // A new revision is a new offer: an earlier decline no longer holds.
        final reset = CustomerResponse(
          views: response.views,
          firstViewedAt: response.firstViewedAt,
          lastViewedAt: response.lastViewedAt,
        );
        await tx.execute(
          '''
          UPDATE publications SET revision = @r:int4, content = @c:jsonb,
            content_hash = @h, response = @resp:jsonb, published_by = @u,
            sent_at = @now:timestamptz, updated_at = @now:timestamptz
          WHERE public_id = @p''',
          {
            'r': revision,
            'c': content.toJson(),
            'h': hash,
            'resp': reset.toJson(),
            'u': a.userId,
            'now': now,
            'p': publicId,
          },
        );
        await _event(tx, a.businessId, id, publicId, 'revised', {
          'revision': revision,
          'total_cents': content.defaultOption.totalCents,
          'options': content.options.length,
        });
      }
      await _touch(tx, a.businessId, id);
      await _outbox.add(
        tx,
        'quote.follow_up',
        {
          'business_id': a.businessId,
          'public_id': publicId,
          'revision': revision,
        },
        runAt: now.add(followUpAfter),
        dedupeKey: 'followup:$publicId:$revision',
      );
      _log({
        'event': 'published',
        'business': a.businessId,
        'revision': revision,
        'options': content.options.length,
      });
      return {
        ..._present((await _load(tx, a.businessId, id))!),
        'changed': true,
      };
    });
  }

  /// Newest first. Pass `next` back as [before] for older events.
  Future<Map<String, Object?>> activity(
    Account a, {
    int? before,
    int limit = 50,
  }) async {
    final n = limit.clamp(1, 200);
    final rows = await _db.query(
      '''
      SELECT e.id, e.quote_id, e.public_id, e.kind, e.data, e.created_at,
        q.number, q.data -> 'customer' ->> 'name' AS customer
      FROM quote_events e
      LEFT JOIN quotes q ON q.business_id = e.business_id AND q.id = e.quote_id
      WHERE e.business_id = @b ${before == null ? '' : 'AND e.id < @before:int8'}
      ORDER BY e.id DESC LIMIT @n:int4''',
      {'b': a.businessId, 'before': before, 'n': n},
    );
    return {
      'events': [
        for (final e in rows)
          {
            'id': e['id'],
            'kind': e['kind'],
            'quote_id': e['quote_id'],
            'quote_number': e['number'],
            'customer': e['customer'] ?? '',
            'at': (e['created_at'] as DateTime).toIso8601String(),
            // The audit fields (IP, browser) stay in the export.
            'data': {
              for (final d in asMap(e['data']).entries)
                if (d.key != 'ip' && d.key != 'user_agent') d.key: d.value,
            },
          },
      ],
      'next': rows.length == n ? rows.last['id'] : null,
    };
  }

  // ---------------------------------------------------------------------------
  // The customer's side
  // ---------------------------------------------------------------------------

  /// The page data for a link, counting the visit unless [countView] is
  /// false (previews, bots, redirects after a form post).
  Future<CustomerView?> open(String publicId, {required bool countView}) async {
    if (!publicIdPattern.hasMatch(publicId)) return null;
    if (!countView) {
      final row = await _publication(_db, publicId);
      return row == null ? null : _view(row);
    }
    return _withPublication(publicId, (tx, row) async {
      final r = CustomerResponse.fromJson(row['response']);
      final now = _clock();
      final updated = CustomerResponse(
        views: r.views + 1,
        firstViewedAt: r.firstViewedAt ?? now,
        lastViewedAt: now,
        approvedAt: r.approvedAt,
        approvedTierId: r.approvedTierId,
        signature: r.signature,
        declinedAt: r.declinedAt,
        declineReason: r.declineReason,
      );
      await _saveResponse(tx, publicId, updated);
      await _touch(tx, row['business_id'] as String, row['quote_id'] as String);
      if (r.views == 0) {
        await _event(
          tx,
          row['business_id'] as String,
          row['quote_id'] as String,
          publicId,
          'viewed',
          {'revision': row['revision']},
        );
        await _notify(tx, row, 'viewed');
      }
      return _view({...row, 'response': updated.toJson()});
    });
  }

  /// Records the customer's approval with an audit trail: who typed their
  /// name, from where, for which option and revision.
  Future<ApproveOutcome> approve(
    String publicId, {
    required String optionId,
    required String name,
    required bool agreed,
    required String ip,
    required String userAgent,
  }) async {
    if (!publicIdPattern.hasMatch(publicId)) return ApproveOutcome.missing;
    final outcome = await _withPublication(publicId, (tx, row) async {
      final q = PublicQuote.fromJson(row['content']);
      final r = CustomerResponse.fromJson(row['response']);
      if (r.approvedAt != null) return ApproveOutcome.alreadyApproved;
      final now = _clock();
      if (now.isAfter(q.validUntil)) return ApproveOutcome.expired;
      final chosen = q.options.length == 1
          ? q.options.single
          : q.option(optionId);
      if (chosen == null) return ApproveOutcome.option;
      final signature = name.trim();
      if (signature.isEmpty || signature.length > 80) {
        return ApproveOutcome.name;
      }
      if (!agreed) return ApproveOutcome.agree;
      await _saveResponse(
        tx,
        publicId,
        CustomerResponse(
          views: r.views,
          firstViewedAt: r.firstViewedAt,
          lastViewedAt: r.lastViewedAt,
          approvedAt: now,
          approvedTierId: chosen.id,
          signature: signature,
        ),
      );
      final businessId = row['business_id'] as String;
      final quoteId = row['quote_id'] as String;
      await _touch(tx, businessId, quoteId);
      await _event(tx, businessId, quoteId, publicId, 'approved', {
        'revision': row['revision'],
        'content_hash': row['content_hash'],
        'option_id': chosen.id,
        'option_name': chosen.name,
        'total_cents': chosen.totalCents,
        'deposit_cents': chosen.depositCents,
        'signature': signature,
        'ip': ip,
        'user_agent': _clip(userAgent, 300),
      });
      await _notify(
        tx,
        row,
        'approved',
        detail:
            '${q.options.length > 1 ? '${chosen.name}, ' : ''}'
            '${Money.format(chosen.totalCents)}. Signed by $signature.',
      );
      return ApproveOutcome.approved;
    });
    if (outcome == ApproveOutcome.approved) {
      _log({'event': 'approved', 'quote': publicId});
    }
    return outcome ?? ApproveOutcome.missing;
  }

  /// Returns false when there's no such quote.
  Future<bool> decline(
    String publicId, {
    required String reason,
    required String ip,
    required String userAgent,
  }) async {
    if (!publicIdPattern.hasMatch(publicId)) return false;
    final found = await _withPublication(publicId, (tx, row) async {
      final r = CustomerResponse.fromJson(row['response']);
      if (r.approvedAt != null || r.declinedAt != null) return true;
      final why = _clip(reason.trim(), 500);
      await _saveResponse(
        tx,
        publicId,
        CustomerResponse(
          views: r.views,
          firstViewedAt: r.firstViewedAt,
          lastViewedAt: r.lastViewedAt,
          declinedAt: _clock(),
          declineReason: why,
        ),
      );
      final businessId = row['business_id'] as String;
      final quoteId = row['quote_id'] as String;
      await _touch(tx, businessId, quoteId);
      await _event(tx, businessId, quoteId, publicId, 'declined', {
        'revision': row['revision'],
        'reason': why,
        'ip': ip,
        'user_agent': _clip(userAgent, 300),
      });
      await _notify(
        tx,
        row,
        'declined',
        detail: why.isEmpty ? '' : 'They said: "$why"',
      );
      return true;
    });
    if (found == true) _log({'event': 'declined', 'quote': publicId});
    return found ?? false;
  }

  /// Records a deposit Stripe says was paid. Idempotent per payment.
  Future<void> depositPaid(
    String publicId, {
    required int amountCents,
    required String paymentId,
  }) async {
    await _withPublication(publicId, (tx, row) async {
      final businessId = row['business_id'] as String;
      final quoteId = row['quote_id'] as String;
      if (row['deposit_status'] == 'paid') {
        if (row['deposit_payment_id'] != paymentId) {
          // Paid twice (two tabs): tell the contractor so they can refund.
          await _event(tx, businessId, quoteId, publicId, 'deposit_duplicate', {
            'amount_cents': amountCents,
            'payment_id': paymentId,
          });
          await _notify(
            tx,
            row,
            'deposit_paid',
            detail:
                'This is a second deposit payment of '
                '${Money.format(amountCents)}. You may want to refund one in '
                'Stripe.',
          );
        }
        return null;
      }
      await tx.execute(
        '''
        UPDATE publications SET deposit_status = 'paid',
          deposit_paid_cents = @amt:int4, deposit_paid_at = @now:timestamptz,
          deposit_payment_id = @pay, updated_at = @now:timestamptz
        WHERE public_id = @p''',
        {'amt': amountCents, 'now': _clock(), 'pay': paymentId, 'p': publicId},
      );
      await _touch(tx, businessId, quoteId);
      await _event(tx, businessId, quoteId, publicId, 'deposit_paid', {
        'amount_cents': amountCents,
        'payment_id': paymentId,
      });
      await _notify(
        tx,
        row,
        'deposit_paid',
        detail: '${Money.format(amountCents)} is on its way to your bank.',
      );
      return null;
    });
    _log({'event': 'deposit_paid', 'quote': publicId, 'cents': amountCents});
  }

  /// Emails the contractor when a sent quote gets no decision. Run by the
  /// `quote.follow_up` job.
  Future<void> followUp(Map<String, Object?> payload) async {
    final publicId = asString(payload['public_id']) ?? '';
    final revision = asInt(payload['revision']);
    await _withPublication(publicId, (tx, row) async {
      if (row['revision'] != revision) return null;
      final r = CustomerResponse.fromJson(row['response']);
      if (r.approvedAt != null || r.declinedAt != null) return null;
      final quote = await tx.one(
        'SELECT status FROM quotes WHERE business_id = @b AND id = @q',
        {'b': row['business_id'], 'q': row['quote_id']},
      );
      // Closed by hand after a phone call.
      if (quote == null ||
          const {'approved', 'declined'}.contains(quote['status'])) {
        return null;
      }
      final seen = r.views == 0
          ? "They haven't opened it yet."
          : 'They opened it ${r.views == 1 ? 'once' : '${r.views} times'}, '
                'last on ${_day(r.lastViewedAt!)}.';
      await _notify(
        tx,
        row,
        'follow_up',
        detail: '$seen A quick call or text now helps close it.',
      );
      await _event(
        tx,
        row['business_id'] as String,
        row['quote_id'] as String,
        publicId,
        'follow_up_sent',
        {'revision': revision},
      );
      return null;
    });
  }

  // ---------------------------------------------------------------------------

  /// Serializes writes to one business's quotes, so sync cursors (sequence
  /// numbers) commit in order and a phone never skips a change.
  static Future<void> _lock(Db tx, String businessId) => tx.execute(
    'SELECT pg_advisory_xact_lock(hashtextextended(@k, 0))',
    {'k': 'quotes:$businessId'},
  );

  static Future<Row?> _load(Db db, String businessId, String id) => db.one(
    '$_select WHERE q.business_id = @b AND q.id = @id',
    {'b': businessId, 'id': id},
  );

  static Future<Row?> _publication(Db db, String publicId) => db.one(
    '''
    SELECT p.*, b.stripe_account_ready,
      q.data -> 'customer' ->> 'name' AS customer, q.number
    FROM publications p
    JOIN businesses b ON b.id = p.business_id
    JOIN quotes q ON q.business_id = p.business_id AND q.id = p.quote_id
    WHERE p.public_id = @p''',
    {'p': publicId},
  );

  /// Runs [fn] holding the owning business's lock, with a fresh read of
  /// the publication. Returns null when it doesn't exist.
  Future<T?> _withPublication<T>(
    String publicId,
    Future<T?> Function(Db tx, Row row) fn,
  ) async {
    if (!publicIdPattern.hasMatch(publicId)) return null;
    return _db.tx((tx) async {
      final head = await tx.one(
        'SELECT business_id FROM publications WHERE public_id = @p',
        {'p': publicId},
      );
      if (head == null) return null;
      await _lock(tx, head['business_id'] as String);
      final row = await _publication(tx, publicId);
      if (row == null) return null;
      return fn(tx, row);
    });
  }

  static Future<void> _saveResponse(
    Db tx,
    String publicId,
    CustomerResponse r,
  ) => tx.execute(
    'UPDATE publications SET response = @r:jsonb WHERE public_id = @p',
    {'r': r.toJson(), 'p': publicId},
  );

  /// Recomputes the stored status and moves the quote to the end of the
  /// sync order, so phones pick up what changed.
  Future<void> _touch(Db tx, String businessId, String quoteId) async {
    final row = await _load(tx, businessId, quoteId);
    if (row == null) return;
    final quote = Quote.fromJson(row['data']);
    if (quote == null) return;
    await tx.execute(
      '''
      UPDATE quotes SET status = @s, seq = nextval('sync_seq'),
        updated_at = @now:timestamptz
      WHERE business_id = @b AND id = @q''',
      {
        's': _effective(quote, row).status.id,
        'now': _clock(),
        'b': businessId,
        'q': quoteId,
      },
    );
  }

  Future<void> _event(
    Db tx,
    String businessId,
    String quoteId,
    String? publicId,
    String kind,
    Map<String, Object?> data,
  ) => tx.execute(
    '''
    INSERT INTO quote_events (business_id, quote_id, public_id, kind, data,
      created_at)
    VALUES (@b, @q, @p, @k, @d:jsonb, @now:timestamptz)''',
    {
      'b': businessId,
      'q': quoteId,
      'p': publicId,
      'k': kind,
      'd': data,
      'now': _clock(),
    },
  );

  Future<void> _notify(Db tx, Row pub, String kind, {String detail = ''}) {
    final content = PublicQuote.fromJson(pub['content']);
    final customer = (pub['customer'] as String?) ?? content.customerName;
    return _outbox.notifyBusiness(
      tx,
      businessId: pub['business_id'] as String,
      sentBy: pub['published_by'] as String?,
      build: (to) => _outbox.templates.quoteEvent(
        to,
        kind: kind,
        quoteLabel: 'Quote #${content.number}',
        customer: customer,
        url: customerUrl(pub['public_id'] as String),
        detail: detail,
      ),
    );
  }

  CustomerView _view(Row row) {
    final paidAt = row['deposit_paid_at'] as DateTime?;
    return CustomerView(
      publicId: row['public_id'] as String,
      businessId: row['business_id'] as String,
      quoteId: row['quote_id'] as String,
      revision: row['revision'] as int,
      quote: PublicQuote.fromJson(row['content']),
      response: CustomerResponse.fromJson(row['response']),
      onlineDeposit: onlineDeposits && row['stripe_account_ready'] == true,
      depositPaidCents: row['deposit_paid_cents'] as int?,
      depositPaidAt: paidAt,
    );
  }

  /// A quote as phones see it: the stored copy with the server's view of
  /// its link and the customer's response folded in.
  Map<String, Object?> _present(Row row) {
    if (row['deleted'] == true) {
      return {'id': row['id'], 'version': row['version'], 'deleted': true};
    }
    final quote = _effective(Quote.fromJson(row['data'])!, row);
    final publicId = row['public_id'] as String?;
    return {
      'id': row['id'],
      'version': row['version'],
      'deleted': false,
      'quote': quote.toJson(),
      'deposit': publicId == null
          ? null
          : {
              'status': row['deposit_status'],
              'paid_cents': row['deposit_paid_cents'],
              'paid_at': (row['deposit_paid_at'] as DateTime?)
                  ?.toIso8601String(),
            },
    };
  }

  /// Status with the link applied: a sent quote is at least "sent", a
  /// decision recorded before the latest send is superseded by it, and the
  /// customer's response wins over both.
  Quote _effective(Quote stored, Row row) {
    final publicId = row['public_id'] as String?;
    if (publicId == null) {
      return stored.copyWith(share: null, response: const CustomerResponse());
    }
    final sentAt = row['sent_at'] as DateTime;
    var status = stored.status;
    final closedBeforeSend =
        stored.closedAt == null || stored.closedAt!.isBefore(sentAt);
    if (status == QuoteStatus.draft || (!status.isOpen && closedBeforeSend)) {
      status = QuoteStatus.sent;
    }
    final response = CustomerResponse.fromJson(row['response']);
    return stored
        .copyWith(
          status: status,
          share: ShareInfo(
            publicId: publicId,
            url: customerUrl(publicId),
            ownerToken: '',
            sentAt: sentAt,
            revision: row['revision'] as int,
          ),
        )
        .applyResponse(response);
  }

  /// What the server stores: the phone's quote without the fields the
  /// server owns (link and customer response).
  static Map<String, Object?> _storable(Quote q) {
    final json = q.toJson();
    json.remove('share');
    json.remove('response');
    return json;
  }

  static String _contentHash(PublicQuote q) {
    final json = q.toJson()
      ..remove('issued_at')
      ..remove('valid_until');
    return sha256Hex(jsonEncode(json));
  }

  static bool _jsonEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !_jsonEquals(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_jsonEquals(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is num && b is num) return a == b;
    return a == b;
  }

  static String _clip(String s, int max) =>
      s.length > max ? s.substring(0, max) : s;

  static String _day(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final u = d.toUtc();
    return '${months[u.month - 1]} ${u.day}';
  }

  static ApiError _missing() => ApiError.notFound('No quote with that id.');
}
