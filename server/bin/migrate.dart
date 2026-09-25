import 'dart:io';

import 'package:jobwalk_server/jobwalk_server.dart';

/// Applies pending migrations and exits. Run it as a release step when
/// JOBWALK_MIGRATE_ON_START is false.
Future<void> main() async {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln('DATABASE_URL is required.');
    exit(78);
  }
  final db = Db.open(url, maxConnections: 1);
  try {
    final applied = await migrate(db);
    stdout.writeln(
      applied.isEmpty
          ? 'Schema is current (version $latestSchemaVersion).'
          : 'Applied migrations ${applied.join(', ')}.',
    );
  } finally {
    await db.close();
  }
}
