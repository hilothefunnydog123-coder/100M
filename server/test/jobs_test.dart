import 'package:jobwalk_server/src/db/pg_limiter.dart';
import 'package:jobwalk_server/src/jobs.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

void main() {
  withDb((db) {
    late DateTime now;
    setUp(() => now = DateTime.utc(2026, 9, 25, 15));

    Worker worker(Map<String, JobHandler> handlers) =>
        Worker(db: db().db, handlers: handlers, clock: () => now);

    test('runs due jobs once, later jobs later', () async {
      final seen = <Object?>[];
      final w = worker({'hello': (p) async => seen.add(p['n'])});
      const q = JobQueue();
      await q.enqueue(db().db, 'hello', {'n': 1}, runAt: now);
      await q.enqueue(db().db, 'hello', {
        'n': 2,
      }, runAt: now.add(const Duration(hours: 1)));
      expect(await w.drain(), 1);
      expect(seen, [1]);
      now = now.add(const Duration(hours: 2));
      expect(await w.drain(), 1);
      expect(seen, [1, 2]);
      expect(await w.drain(), 0);
    });

    test('retries with backoff, then gives up', () async {
      var calls = 0;
      final w = worker({
        'flaky': (_) async {
          calls++;
          throw StateError('down');
        },
      });
      await const JobQueue().enqueue(
        db().db,
        'flaky',
        {},
        runAt: now,
        maxAttempts: 3,
      );
      for (var i = 0; i < 5; i++) {
        await w.drain();
        now = now.add(const Duration(hours: 2));
      }
      expect(calls, 3);
      final job = (await db().db.one('SELECT * FROM jobs'))!;
      expect(job['failed'], isTrue);
      expect(job['done_at'], isNotNull);
      expect(job['last_error'], contains('down'));
    });

    test('permanent errors and unknown kinds fail at once', () async {
      final w = worker({
        'bad': (_) async => throw PermanentJobError('no such user'),
      });
      await const JobQueue().enqueue(db().db, 'bad', {}, runAt: now);
      await const JobQueue().enqueue(db().db, 'unknown', {}, runAt: now);
      await w.drain();
      final rows = await db().db.query('SELECT failed, attempts FROM jobs');
      expect(
        rows.every((r) => r['failed'] == true && r['attempts'] == 1),
        isTrue,
      );
    });

    test('dedupe keys keep one pending job', () async {
      const q = JobQueue();
      for (var i = 0; i < 3; i++) {
        await q.enqueue(db().db, 'x', {}, runAt: now, dedupeKey: 'k');
      }
      expect(await db().db.query('SELECT * FROM jobs'), hasLength(1));
      await worker({'x': (_) async {}}).drain();
      await q.enqueue(db().db, 'x', {}, runAt: now, dedupeKey: 'k');
      expect(await db().db.query('SELECT * FROM jobs'), hasLength(2));
    });

    test('two workers never run the same job', () async {
      var runs = 0;
      JobHandler slow() => (_) async {
        runs++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      };
      for (var i = 0; i < 20; i++) {
        await const JobQueue().enqueue(db().db, 'slow', {'i': i}, runAt: now);
      }
      final a = worker({'slow': slow()});
      final b = worker({'slow': slow()});
      await Future.wait([a.drain(), b.drain()]);
      expect(runs, 20);
    });

    test('the loop starts and stops cleanly', () async {
      var ran = false;
      final w = Worker(
        db: db().db,
        handlers: {'x': (_) async => ran = true},
        pollInterval: const Duration(milliseconds: 10),
      );
      await const JobQueue().enqueue(
        db().db,
        'x',
        {},
        runAt: DateTime.now().toUtc(),
      );
      w.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await w.stop();
      expect(ran, isTrue);
    });

    test('Postgres limiter shares buckets and refills over time', () async {
      final limiter = PgLimiter(
        db().db,
        capacity: 2,
        refillEvery: const Duration(minutes: 1),
        clock: () => now,
      );
      expect(await limiter.acquire('ip:1'), isNull);
      expect(await limiter.acquire('ip:1'), isNull);
      final wait = await limiter.acquire('ip:1');
      expect(wait, isNotNull);
      expect(wait!.inSeconds, inInclusiveRange(59, 61));
      expect(await limiter.acquire('ip:2'), isNull);
      now = now.add(const Duration(minutes: 2));
      expect(await limiter.acquire('ip:1'), isNull);
    });
  });
}
