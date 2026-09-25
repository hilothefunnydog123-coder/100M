import 'dart:async';
import 'dart:io';

import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'setup.dart';

Future<void> main() async {
  final setup = await Setup.load();
  final config = setup.config;
  final app = setup.app;
  await app.start();

  final server = await shelf_io.serve(
    app.handler,
    InternetAddress.anyIPv4,
    config.port,
  );
  server
    ..autoCompress = true
    ..idleTimeout = const Duration(seconds: 75);
  stdoutLog({
    'event': 'listening',
    'port': server.port,
    'env': config.env,
    'model': config.fakeModel ? 'demo' : config.drafter.model,
    'effort': config.drafter.effort,
    'prompt_version': promptVersion,
    'schema': latestSchemaVersion,
    'billing': config.stripeEnabled,
    'email': config.emailProvider,
    'storage': config.storage,
  });

  // On SIGTERM: refuse new work, let in-flight requests (drafts can take
  // minutes) finish, stop the worker, then close the pool.
  var stopping = false;
  Future<void> shutdown(ProcessSignal signal) async {
    if (stopping) return;
    stopping = true;
    stdoutLog({'event': 'shutting_down', 'signal': '$signal'});
    app.draining = true;
    try {
      await server.close().timeout(
        config.draftTimeout + const Duration(seconds: 10),
      );
    } on TimeoutException {
      await server.close(force: true);
    }
    await app.stop();
    await app.db.close();
    stdoutLog({'event': 'stopped'});
    exit(0);
  }

  ProcessSignal.sigterm.watch().listen(shutdown);
  ProcessSignal.sigint.watch().listen(shutdown);
}
