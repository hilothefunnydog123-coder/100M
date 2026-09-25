import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

import 'support/harness.dart';
import 'support/test_db.dart';

void main() {
  withDb((testDb) {
    late Harness h;
    setUp(() => h = Harness(testDb()));

    test('cleanup removes what has expired and schedules itself', () async {
      final dana = await h.owner('dana@example.com');
      final old = h.now.subtract(const Duration(days: 100));
      await h.db.execute(
        '''
        INSERT INTO sessions (token_hash, user_id, expires_at)
        VALUES ('expired', @u, @old:timestamptz)''',
        {'u': dana.account.userId, 'old': old},
      );
      await h.db.execute(
        '''
        INSERT INTO jobs (kind, done_at, failed) VALUES
          ('email.send', @old:timestamptz, false),
          ('email.send', @old:timestamptz, true),
          ('email.send', @recent:timestamptz, true)''',
        {'old': old, 'recent': h.now},
      );
      await h.db.execute(
        "INSERT INTO rate_limits VALUES ('ip:x', 1, @old:timestamptz)",
        {'old': old},
      );
      await h.db.execute(
        '''
        INSERT INTO drafts (business_id, state, response, created_at)
        VALUES (@b, 'done', '{"draft": {}}', @old:timestamptz)''',
        {'b': dana.account.businessId, 'old': old},
      );
      await h.db.execute(
        "INSERT INTO stripe_events VALUES ('evt_1', 'x', @old:timestamptz)",
        {'old': old.subtract(const Duration(days: 100))},
      );

      final counts = await h.app.maintenance.run();
      expect(counts['sessions'], 1);
      expect(counts['jobs'], 2, reason: 'recent failures are kept');
      expect(counts['rate_limits'], 1);
      expect(counts['draft_responses'], 1);
      expect(counts['stripe_events'], 1);
      expect(
        await h.accounts.authenticate(dana.token),
        isNotNull,
        reason: 'live sessions stay',
      );
      final next = await h.db.query(
        "SELECT run_at FROM jobs WHERE kind = 'maintenance.cleanup'",
      );
      expect(next.single['run_at'], DateTime.utc(2026, 9, 25, 16));
    });

    test('scheduling is deduplicated across instances', () async {
      await h.app.maintenance.schedule();
      await h.app.maintenance.schedule();
      final jobs = await h.db.query(
        "SELECT id FROM jobs WHERE kind = 'maintenance.cleanup'",
      );
      expect(jobs, hasLength(1));
      h.advance(const Duration(hours: 1));
      await h.runJobs();
      final pending = await h.db.query(
        "SELECT run_at FROM jobs WHERE kind = 'maintenance.cleanup' "
        'AND done_at IS NULL',
      );
      expect(pending.single['run_at'], DateTime.utc(2026, 9, 25, 17));
    });

    test('start schedules cleanup and the worker can be kicked', () async {
      await h.app.start(runWorker: true);
      addTearDown(h.app.stop);
      await h.accounts.requestCode('pat@example.com', ip: '1.1.1.1');
      for (var i = 0; i < 40 && h.emails.sent.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(h.emails.sent, hasLength(1), reason: 'kicked, not polled');
    });
  });

  test('metrics render in the Prometheus text format', () {
    final m = Metrics();
    m.counter('c_total', 'A counter.', labels: ['k'])
      ..inc(['a'])
      ..inc(['a'], 2)
      ..inc(['quote"d']);
    m.histogram('h_seconds', 'A histogram.', buckets: const [0.1, 1])
      ..observe(0.05)
      ..observe(0.5)
      ..observe(5);
    m.gauge('g', 'A gauge.', () => 7);
    final text = m.render();
    expect(text, contains('# TYPE c_total counter'));
    expect(text, contains('c_total{k="a"} 3'));
    expect(text, contains(r'c_total{k="quote\"d"} 1'));
    expect(text, contains('h_seconds_bucket{le="0.1"} 1'));
    expect(text, contains('h_seconds_bucket{le="1"} 2'));
    expect(text, contains('h_seconds_bucket{le="+Inf"} 3'));
    expect(text, contains('h_seconds_count 3'));
    expect(text, contains('g 7'));
  });
}
