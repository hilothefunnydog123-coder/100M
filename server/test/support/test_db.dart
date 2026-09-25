import 'dart:io';
import 'dart:math';

import 'package:jobwalk_server/src/db/database.dart';
import 'package:jobwalk_server/src/db/migrations.dart';
import 'package:test/test.dart';

/// Postgres for integration tests. Each test file gets its own database,
/// migrated once, and every test starts from empty tables.
///
/// Set TEST_DATABASE_URL to an admin connection (default: local postgres).
/// Tests are skipped when no server is reachable, unless REQUIRE_DB=1 (CI).
class TestDb {
  TestDb._(this.db, this._admin, this.name);

  final Db db;
  final Db _admin;
  final String name;

  static final adminUrl =
      Platform.environment['TEST_DATABASE_URL'] ??
      'postgres://postgres:postgres@localhost:5432/postgres';

  static Future<TestDb?> create() async {
    final admin = Db.open(adminUrl, maxConnections: 1);
    if (!await admin.ping()) {
      await admin.close();
      if (Platform.environment['REQUIRE_DB'] == '1') {
        throw StateError('No Postgres at $adminUrl');
      }
      return null;
    }
    final name =
        'jobwalk_test_${pid}_${Random().nextInt(1 << 30).toRadixString(36)}';
    await admin.script('CREATE DATABASE $name');
    final url = Uri.parse(adminUrl).replace(path: '/$name').toString();
    final db = Db.open(url, maxConnections: 8);
    await migrate(db);
    return TestDb._(db, admin, name);
  }

  static const _tables = [
    'businesses',
    'users',
    'sign_in_codes',
    'sessions',
    'quotes',
    'publications',
    'quote_events',
    'photos',
    'drafts',
    'jobs',
    'waitlist',
    'rate_limits',
    'stripe_events',
  ];

  Future<void> reset() =>
      db.script('TRUNCATE ${_tables.join(', ')} RESTART IDENTITY CASCADE');

  Future<void> drop() async {
    await db.close();
    await _admin.script('DROP DATABASE IF EXISTS $name WITH (FORCE)');
    await _admin.close();
  }
}

/// Declares [body] with a fresh database, or skips when Postgres is absent.
void withDb(void Function(TestDb Function() db) body) {
  TestDb? testDb;
  setUpAll(() async => testDb = await TestDb.create());
  tearDownAll(() async => testDb?.drop());
  setUp(() async {
    if (testDb == null) markTestSkipped('No Postgres available.');
    await testDb?.reset();
  });
  body(() => testDb!);
}
