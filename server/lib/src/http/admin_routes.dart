import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../common.dart';
import '../db/database.dart';
import '../integrations/stripe.dart' show constantTimeEquals;
import 'respond.dart';

/// Operator endpoints behind `ADMIN_TOKEN`. Without a token configured
/// they don't exist.
class AdminRoutes {
  AdminRoutes({
    required Db db,
    required String? token,
    Clock clock = systemClock,
  }) : _db = db,
       _token = token,
       _clock = clock;

  final Db _db;
  final String? _token;
  final Clock _clock;

  Router get router => Router()
    ..get('/admin/stats', _guard(_stats))
    ..get('/admin/waitlist.csv', _guard(_waitlist))
    ..get('/admin/jobs', _guard(_jobs))
    ..post('/admin/jobs/<id>/retry', (Request r, String id) async {
      _check(r);
      return _retry(r, id);
    });

  void _check(Request r) {
    final token = _token;
    if (token == null || token.length < 16) throw ApiError.notFound();
    if (!constantTimeEquals(bearerToken(r) ?? '', token)) {
      throw ApiError.notFound();
    }
  }

  Handler _guard(Future<Response> Function(Request) fn) => (r) async {
    _check(r);
    return fn(r);
  };

  Future<Response> _stats(Request r) async {
    final now = _clock();
    final params = {
      'd7': now.subtract(const Duration(days: 7)),
      'd30': now.subtract(const Duration(days: 30)),
    };
    final totals = await _db.one('''
      SELECT
        (SELECT count(*) FROM businesses)::int AS businesses,
        (SELECT count(*) FROM users)::int AS users,
        (SELECT count(*) FROM users
          WHERE last_seen_at > @d7:timestamptz)::int AS users_active_7d,
        (SELECT count(*) FROM quotes WHERE NOT deleted)::int AS quotes,
        (SELECT count(*) FROM publications)::int AS quotes_sent,
        (SELECT count(*) FROM quote_events WHERE kind = 'sent'
          AND created_at > @d30:timestamptz)::int AS sent_30d,
        (SELECT count(*) FROM quote_events WHERE kind = 'approved'
          AND created_at > @d30:timestamptz)::int AS approved_30d,
        (SELECT COALESCE(sum((data ->> 'total_cents')::bigint), 0)
          FROM quote_events WHERE kind = 'approved'
          AND created_at > @d30:timestamptz)::bigint AS approved_cents_30d,
        (SELECT count(*) FROM drafts
          WHERE created_at > @d30:timestamptz)::int AS drafts_30d,
        (SELECT count(*) FROM drafts WHERE state = 'failed'
          AND created_at > @d30:timestamptz)::int AS drafts_failed_30d,
        (SELECT COALESCE(sum(cost_micros), 0) FROM drafts
          WHERE created_at > @d30:timestamptz)::bigint AS draft_cost_micros_30d,
        (SELECT COALESCE(sum(deposit_paid_cents), 0) FROM publications
          WHERE deposit_paid_at > @d30:timestamptz)::bigint AS deposits_cents_30d,
        (SELECT count(*) FROM jobs WHERE done_at IS NULL)::int AS jobs_pending,
        (SELECT count(*) FROM jobs WHERE failed
          AND done_at > @d7:timestamptz)::int AS jobs_failed_7d,
        (SELECT count(*) FROM waitlist)::int AS waitlist''', params);
    final plans = await _db.query(
      'SELECT plan, plan_status, count(*)::int AS n FROM businesses '
      'GROUP BY 1, 2 ORDER BY 1, 2',
    );
    final t = totals!;
    return jsonResponse(200, {
      ...t,
      'draft_cost_usd_30d': (t['draft_cost_micros_30d'] as int) / 1e6,
      'plans': [
        for (final p in plans)
          {'plan': p['plan'], 'status': p['plan_status'], 'businesses': p['n']},
      ],
      'at': now.toIso8601String(),
    });
  }

  Future<Response> _waitlist(Request r) async {
    final rows = await _db.query(
      'SELECT email, trade, crew, created_at FROM waitlist ORDER BY created_at',
    );
    String cell(Object? v) {
      var s = '$v';
      // Keep spreadsheets from running a cell as a formula.
      if (s.startsWith(RegExp(r'[=+\-@]'))) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    final csv = StringBuffer('email,trade,crew,joined_at\n');
    for (final row in rows) {
      csv.writeln(
        [
          cell(row['email']),
          cell(row['trade']),
          cell(row['crew']),
          cell((row['created_at'] as DateTime).toIso8601String()),
        ].join(','),
      );
    }
    return Response.ok(
      csv.toString(),
      headers: {
        'content-type': 'text/csv; charset=utf-8',
        'content-disposition': 'attachment; filename="waitlist.csv"',
      },
    );
  }

  Future<Response> _jobs(Request r) async {
    final failed = r.url.queryParameters['state'] != 'pending';
    final rows = await _db.query('''
      SELECT id, kind, attempts, max_attempts, run_at, last_error, created_at,
        done_at
      FROM jobs WHERE ${failed ? 'failed' : 'done_at IS NULL'}
      ORDER BY id DESC LIMIT 100''');
    String? iso(Object? d) => (d as DateTime?)?.toIso8601String();
    return jsonResponse(200, {
      'jobs': [
        for (final j in rows)
          {
            'id': j['id'],
            'kind': j['kind'],
            'attempts': j['attempts'],
            'max_attempts': j['max_attempts'],
            'run_at': iso(j['run_at']),
            'created_at': iso(j['created_at']),
            'done_at': iso(j['done_at']),
            'last_error': j['last_error'],
          },
      ],
    });
  }

  Future<Response> _retry(Request r, String id) async {
    final jobId = int.tryParse(id);
    if (jobId == null) throw ApiError.notFound('No such job.');
    try {
      final n = await _db.execute(
        '''
        UPDATE jobs SET failed = false, done_at = NULL, attempts = 0,
          locked_until = NULL, run_at = @now:timestamptz
        WHERE id = @id:int8 AND failed''',
        {'now': _clock(), 'id': jobId},
      );
      if (n == 0) throw ApiError.notFound('No failed job with that id.');
    } on Object catch (e) {
      if (isUniqueViolation(e)) {
        throw ApiError(409, 'duplicate', 'An identical job is already queued.');
      }
      rethrow;
    }
    return jsonResponse(200, {'ok': true});
  }
}
