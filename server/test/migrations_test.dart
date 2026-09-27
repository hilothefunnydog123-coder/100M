import 'package:jobwalk_server/src/db/database.dart';
import 'package:jobwalk_server/src/db/migrations.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

void main() {
  withDb((db) {
    test('migrations are applied once and recorded', () async {
      final again = await migrate(db().db);
      expect(again, isEmpty);
      final rows = await db().db.query(
        'SELECT version FROM schema_migrations ORDER BY version',
      );
      expect(rows.map((r) => r['version']), [for (final m in migrations) m.$1]);
      expect(latestSchemaVersion, migrations.last.$1);
    });

    test('row level security keeps every role but the owner out', () async {
      final d = db().db;
      final open = await d.query('''
        SELECT c.relname FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = current_schema() AND c.relkind IN ('r', 'p')
          AND NOT c.relrowsecurity''');
      expect(open, isEmpty, reason: 'Enable row level security on new tables.');

      // Like Supabase's API roles on older projects: granted, but no policy.
      await d.execute("INSERT INTO waitlist (email) VALUES ('a@b.co')");
      final role = 'jobwalk_api_${DateTime.now().microsecondsSinceEpoch}';
      await d.withConnection((conn) async {
        await conn.script(
          'CREATE ROLE $role NOLOGIN; GRANT SELECT ON waitlist TO $role',
        );
        try {
          await conn.script('SET ROLE $role');
          expect(await conn.query('SELECT * FROM waitlist'), isEmpty);
        } finally {
          await conn.script('RESET ROLE; DROP OWNED BY $role; DROP ROLE $role');
        }
      });
      expect(await d.query('SELECT * FROM waitlist'), hasLength(1));
    });

    test('transactions roll back on error and nest', () async {
      final d = db().db;
      await expectLater(
        d.tx((tx) async {
          await tx.execute("INSERT INTO waitlist (email) VALUES ('a@b.co')");
          await tx.tx((inner) async {
            expect(inner.inTransaction, isTrue);
          });
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(await d.query('SELECT * FROM waitlist'), isEmpty);
      await d.tx(
        (tx) => tx.execute("INSERT INTO waitlist (email) VALUES ('a@b.co')"),
      );
      expect(await d.query('SELECT * FROM waitlist'), hasLength(1));
    });

    test('jsonb and timestamps round trip', () async {
      final d = db().db;
      final at = DateTime.utc(2026, 9, 25, 15, 30);
      await d.execute(
        'INSERT INTO businesses (id, profile, created_at) '
        "VALUES ('b_1', @p:jsonb, @at:timestamptz)",
        {
          'p': {
            'name': 'Brightline',
            'trades': ['painting'],
          },
          'at': at,
        },
      );
      final row = (await d.one('SELECT * FROM businesses'))!;
      expect(row['profile'], {
        'name': 'Brightline',
        'trades': ['painting'],
      });
      expect((row['created_at'] as DateTime).isAtSameMomentAs(at), isTrue);
      expect(row['plan'], 'trial');
    });
  });

  test('TLS by default, except for local and private hosts', () {
    expect(Db.defaultSslMode('localhost'), 'disable');
    expect(Db.defaultSslMode('db'), 'disable');
    expect(Db.defaultSslMode('jobwalk-db.flycast'), 'disable');
    expect(Db.defaultSslMode('top2.nearest.of.jobwalk-db.internal'), 'disable');
    expect(
      Db.defaultSslMode('ep-cool-1234.us-east-2.aws.neon.tech'),
      'require',
    );
    expect(Db.defaultSslMode('db.abcdefgh.supabase.co'), 'require');
    expect(Db.defaultSslMode('aws-0-us-east-1.pooler.supabase.com'), 'require');
  });
}
