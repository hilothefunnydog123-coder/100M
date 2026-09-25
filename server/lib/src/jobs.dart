import 'dart:async';
import 'dart:math';

import 'common.dart';
import 'db/database.dart';

typedef JobHandler = Future<void> Function(Map<String, Object?> payload);

/// Thrown by a handler when retrying can't help (bad address, missing row).
class PermanentJobError implements Exception {
  PermanentJobError(this.message);

  final String message;

  @override
  String toString() => 'PermanentJobError: $message';
}

/// Durable background work in Postgres. Enqueue inside the same transaction
/// as the change that caused it, so a job exists only if the change does.
class JobQueue {
  const JobQueue();

  /// Adds a job. With [dedupeKey], a second pending job with the same key
  /// is silently dropped.
  Future<void> enqueue(
    Db db,
    String kind,
    Map<String, Object?> payload, {
    required DateTime runAt,
    String? dedupeKey,
    int maxAttempts = 6,
  }) => db.execute(
    '''
    INSERT INTO jobs (kind, payload, run_at, dedupe_key, max_attempts)
    VALUES (@kind, @payload:jsonb, @run:timestamptz, @dedupe, @max:int4)
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL AND done_at IS NULL
    DO NOTHING''',
    {
      'kind': kind,
      'payload': payload,
      'run': runAt,
      'dedupe': dedupeKey,
      'max': maxAttempts,
    },
  );
}

/// Runs due jobs. Safe with several instances: rows are claimed with
/// `FOR UPDATE SKIP LOCKED` and leased for [leaseFor].
class Worker {
  Worker({
    required Db db,
    required this.handlers,
    Clock? clock,
    this.batchSize = 10,
    this.pollInterval = const Duration(seconds: 2),
    this.leaseFor = const Duration(minutes: 2),
    LogSink? log,
    void Function(String kind, bool ok)? onJob,
  }) : _db = db,
       _clock = clock ?? systemClock,
       _log = log ?? ((_) {}),
       _onJob = onJob ?? ((_, _) {});

  final Map<String, JobHandler> handlers;
  final int batchSize;
  final Duration pollInterval;
  final Duration leaseFor;
  final Db _db;
  final Clock _clock;
  final LogSink _log;
  final void Function(String, bool) _onJob;
  final _random = Random();

  bool _running = false;
  Future<void>? _loop;

  /// Claims and runs one batch. Returns how many jobs ran.
  Future<int> runOnce() async {
    final now = _clock();
    final jobs = await _db.query(
      '''
      UPDATE jobs SET locked_until = @lease:timestamptz, attempts = attempts + 1
      WHERE id IN (
        SELECT id FROM jobs
        WHERE done_at IS NULL AND run_at <= @now:timestamptz
          AND (locked_until IS NULL OR locked_until < @now:timestamptz)
        ORDER BY run_at, id
        LIMIT @n:int4
        FOR UPDATE SKIP LOCKED)
      RETURNING id, kind, payload, attempts, max_attempts''',
      {'now': now, 'lease': now.add(leaseFor), 'n': batchSize},
    );
    for (final job in jobs) {
      await _run(job);
    }
    return jobs.length;
  }

  /// Runs batches until no job is due. For tests and one-off tools.
  Future<int> drain({int maxBatches = 100}) async {
    var total = 0;
    for (var i = 0; i < maxBatches; i++) {
      final n = await runOnce();
      if (n == 0) break;
      total += n;
    }
    return total;
  }

  Future<void> _run(Row job) async {
    final id = job['id'] as int;
    final kind = job['kind'] as String;
    final attempts = job['attempts'] as int;
    final handler = handlers[kind];
    try {
      if (handler == null) throw PermanentJobError('No handler for "$kind".');
      await handler(
        (job['payload'] as Map?)?.cast<String, Object?>() ?? const {},
      );
      await _db.execute(
        'UPDATE jobs SET done_at = @now:timestamptz, locked_until = NULL, '
        'last_error = NULL WHERE id = @id:int8',
        {'now': _clock(), 'id': id},
      );
      _onJob(kind, true);
    } on Object catch (e) {
      final permanent =
          e is PermanentJobError || attempts >= (job['max_attempts'] as int);
      final message = '$e';
      final error = message.length > 1000
          ? message.substring(0, 1000)
          : message;
      if (permanent) {
        await _db.execute(
          'UPDATE jobs SET done_at = @now:timestamptz, failed = true, '
          'locked_until = NULL, last_error = @err WHERE id = @id:int8',
          {'now': _clock(), 'err': error, 'id': id},
        );
      } else {
        await _db.execute(
          'UPDATE jobs SET run_at = @retry:timestamptz, locked_until = NULL, '
          'last_error = @err WHERE id = @id:int8',
          {'retry': _clock().add(backoff(attempts)), 'err': error, 'id': id},
        );
      }
      _onJob(kind, false);
      _log({
        'event': permanent ? 'job_failed' : 'job_retry',
        'kind': kind,
        'job': id,
        'attempts': attempts,
        'error': message.length > 300 ? message.substring(0, 300) : message,
      });
    }
  }

  /// 30 s, 1 min, 2 min... capped at an hour, with jitter.
  Duration backoff(int attempts) {
    final base = 30 * pow(2, max(0, attempts - 1)).toInt();
    final capped = min(base, 3600);
    return Duration(seconds: capped + _random.nextInt(1 + capped ~/ 10));
  }

  Completer<void>? _wake;
  Timer? _kickTimer;

  /// Checks for due jobs soon instead of at the next poll. The short delay
  /// lets the transaction that queued the job commit first.
  void kick() {
    if (!_running || _kickTimer != null) return;
    _kickTimer = Timer(const Duration(milliseconds: 50), () {
      _kickTimer = null;
      final wake = _wake;
      if (wake != null && !wake.isCompleted) wake.complete();
    });
  }

  void start() {
    if (_running) return;
    _running = true;
    _loop = () async {
      while (_running) {
        var ran = 0;
        try {
          ran = await runOnce();
        } on Object catch (e) {
          _log({'event': 'worker_error', 'error': '$e'});
        }
        if (ran == 0 && _running) {
          final wake = _wake = Completer<void>();
          final timer = Timer(pollInterval, () {
            if (!wake.isCompleted) wake.complete();
          });
          await wake.future;
          timer.cancel();
        }
      }
    }();
  }

  /// Finishes the current batch, then stops.
  Future<void> stop() async {
    _running = false;
    _kickTimer?.cancel();
    _kickTimer = null;
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
    await _loop;
  }
}
