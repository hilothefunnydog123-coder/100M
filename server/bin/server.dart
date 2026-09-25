import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:spotcheck_server/spotcheck_server.dart';

Future<void> main() async {
  final config = ServerConfig.fromEnvironment(Platform.environment);

  final CheckAnalyzer analyzer = config.fakeModel
      ? DemoAnalyzer()
      : Analyzer(
          api: ClaudeClient(apiKey: config.apiKey!, baseUrl: config.apiBaseUrl),
          config: config.analyzer,
        );

  final api = SpotCheckApi(
    analyzer: analyzer,
    model: config.fakeModel ? 'demo' : config.analyzer.model,
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
    'SpotCheck API listening on :${server.port} '
    '(${config.fakeModel ? 'demo analyzer' : config.analyzer.model}, '
    'effort ${config.analyzer.effort}, prompt $promptVersion)',
  );

  // Finish in-flight analyses before exiting on SIGTERM (e.g. Cloud Run).
  ProcessSignal.sigterm.watch().listen((_) async {
    await server.close();
    exit(0);
  });
}
