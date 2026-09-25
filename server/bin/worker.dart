import 'dart:io';

import 'package:jobwalk_server/jobwalk_server.dart';

import 'setup.dart';

/// Runs background jobs without serving HTTP, for deployments that scale
/// web and worker processes separately.
Future<void> main() async {
  final setup = await Setup.load();
  final app = setup.app;
  await app.start(runWorker: true);
  stdoutLog({'event': 'worker_running'});
  Future<void> stop(ProcessSignal signal) async {
    await app.stop();
    await app.db.close();
    exit(0);
  }

  ProcessSignal.sigterm.watch().listen(stop);
  ProcessSignal.sigint.watch().listen(stop);
}
