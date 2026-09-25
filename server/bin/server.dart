import 'dart:io';

import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final config = ServerConfig.fromEnvironment(Platform.environment);

  final QuoteDrafter drafter = config.fakeModel
      ? DemoDrafter()
      : Drafter(
          api: ClaudeClient(apiKey: config.apiKey!, baseUrl: config.apiBaseUrl),
          config: config.drafter,
        );

  final api = JobwalkApi(
    drafter: drafter,
    quotes: FileQuoteStore(Directory('${config.dataDir}/quotes')),
    waitlist: FileWaitlistStore(File('${config.dataDir}/waitlist.jsonl')),
    model: config.fakeModel ? 'demo' : config.drafter.model,
    publicBaseUrl: config.publicBaseUrl,
    corsOrigins: config.corsOrigins,
    installLimiter: RateLimiter(
      capacity: config.installBurst,
      refillEvery: config.installRefill,
    ),
    ipLimiter: RateLimiter(
      capacity: config.ipBurst,
      refillEvery: config.ipRefill,
    ),
    concurrency: ConcurrencyLimiter(
      maxConcurrent: config.maxConcurrent,
      maxQueued: config.maxQueued,
    ),
  );

  final server = await shelf_io.serve(
    api.handler,
    InternetAddress.anyIPv4,
    config.port,
  );
  server.autoCompress = true;
  stdout.writeln(
    'Jobwalk listening on :${server.port} '
    '(${config.fakeModel ? 'sample drafts' : config.drafter.model}, '
    'effort ${config.drafter.effort}, prompt $promptVersion, '
    'data in ${config.dataDir})',
  );

  // Finish in-flight drafts before exiting on SIGTERM.
  ProcessSignal.sigterm.watch().listen((_) async {
    await server.close();
    exit(0);
  });
}
