import '../common.dart';
import '../db/database.dart';
import 'outbox.dart';

/// Hourly housekeeping: expired sessions and codes, old jobs, stale
/// rate-limit buckets, and draft responses past their replay window.
class Maintenance {
  Maintenance({
    required Db db,
    required Outbox outbox,
    Clock clock = systemClock,
    LogSink? log,
  }) : _db = db,
       _outbox = outbox,
       _clock = clock,
       _log = log ?? ((_) {});

  final Db _db;
  final Outbox _outbox;
  final Clock _clock;
  final LogSink _log;

  static const kind = 'maintenance.cleanup';

  /// Queues the next run at the top of the next hour. Every instance calls
  /// this at startup; the dedupe key keeps one run per hour.
  Future<void> schedule() async {
    final now = _clock();
    final next = DateTime.utc(now.year, now.month, now.day, now.hour + 1);
    await _outbox.add(
      _db,
      kind,
      const {},
      runAt: next,
      dedupeKey: 'cleanup:${next.toIso8601String()}',
    );
  }

  Future<Map<String, int>> run([Map<String, Object?> _ = const {}]) async {
    final now = _clock();
    DateTime ago(Duration d) => now.subtract(d);
    final counts = <String, int>{
      'sessions': await _db.execute(
        'DELETE FROM sessions WHERE expires_at < @t:timestamptz',
        {'t': now},
      ),
      'codes': await _db.execute(
        'DELETE FROM sign_in_codes WHERE expires_at < @t:timestamptz',
        {'t': ago(const Duration(hours: 1))},
      ),
      'jobs': await _db.execute(
        '''
        DELETE FROM jobs WHERE done_at IS NOT NULL AND (
          (NOT failed AND done_at < @done:timestamptz) OR
          (failed AND done_at < @failed:timestamptz))''',
        {
          'done': ago(const Duration(days: 14)),
          'failed': ago(const Duration(days: 60)),
        },
      ),
      'rate_limits': await _db.execute(
        'DELETE FROM rate_limits WHERE updated_at < @t:timestamptz',
        {'t': ago(const Duration(days: 1))},
      ),
      'draft_responses': await _db.execute(
        'UPDATE drafts SET response = NULL '
        'WHERE response IS NOT NULL AND created_at < @t:timestamptz',
        {'t': ago(const Duration(days: 7))},
      ),
      'stripe_events': await _db.execute(
        'DELETE FROM stripe_events WHERE received_at < @t:timestamptz',
        {'t': ago(const Duration(days: 90))},
      ),
    };
    _log({'event': 'cleanup', ...counts});
    await schedule();
    return counts;
  }
}
