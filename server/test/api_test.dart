import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:spotcheck_core/spotcheck_core.dart';
import 'package:spotcheck_server/spotcheck_server.dart';
import 'package:test/test.dart';

import 'fakes.dart';

class StubAnalyzer implements CheckAnalyzer {
  StubAnalyzer(this.behavior);

  Future<Analysis> Function(CheckRequest request) behavior;
  int calls = 0;

  @override
  Future<Analysis> analyze(CheckRequest request, {String? id, String? userId}) {
    calls++;
    return behavior(request);
  }
}

Future<Analysis> demo(CheckRequest request) =>
    DemoAnalyzer(delay: Duration.zero).analyze(request);

const installId = 'install_abc123';

Map<String, Object?> validBody({String note = ''}) =>
    checkRequest(note: note).toJson();

void main() {
  late StubAnalyzer analyzer;
  late List<Map<String, Object?>> logs;
  late SpotCheckApi api;

  SpotCheckApi build({
    int installBurst = 10,
    ConcurrencyLimiter? concurrency,
    List<String> cors = const ['*'],
    Duration timeout = const Duration(seconds: 170),
  }) => SpotCheckApi(
    analyzer: analyzer,
    installLimiter: RateLimiter(
      capacity: installBurst,
      refillEvery: const Duration(minutes: 10),
    ),
    ipLimiter: RateLimiter(
      capacity: 100,
      refillEvery: const Duration(minutes: 1),
    ),
    concurrency:
        concurrency ?? ConcurrencyLimiter(maxConcurrent: 4, maxQueued: 4),
    corsOrigins: cors,
    model: 'claude-opus-5-5',
    analysisTimeout: timeout,
    log: logs.add,
  );

  setUp(() {
    analyzer = StubAnalyzer(demo);
    logs = [];
    api = build();
  });

  Future<Response> post(
    Object? body, {
    Map<String, String> headers = const {'x-install-id': installId},
    SpotCheckApi? using,
  }) async => (using ?? api).handler(
    Request(
      'POST',
      Uri.parse('http://localhost/v1/checks'),
      body: body is String ? body : jsonEncode(body),
      headers: {'content-type': 'application/json', ...headers},
    ),
  );

  Future<Map<String, Object?>> jsonOf(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  test('health check reports the model and prompt version', () async {
    final r = await api.handler(
      Request('GET', Uri.parse('http://localhost/healthz')),
    );
    expect(r.statusCode, 200);
    final body = await jsonOf(r);
    expect(body['ok'], isTrue);
    expect(body['model'], 'claude-opus-5-5');
    expect(body['prompt_version'], promptVersion);
  });

  test('analyzes a valid check', () async {
    final r = await post(validBody());
    expect(r.statusCode, 200);
    expect(r.headers['cache-control'], 'no-store');
    final result = CheckResult.fromJson(await jsonOf(r));
    expect(result.status, CheckStatus.complete);
    expect(result.demo, isTrue);
    expect(analyzer.calls, 1);
  });

  test('requires an install id', () async {
    final r = await post(validBody(), headers: const {});
    expect(r.statusCode, 400);
    expect(((await jsonOf(r))['error'] as Map)['code'], 'missing_install_id');
    expect(analyzer.calls, 0);
  });

  test('rejects malformed JSON and invalid checks', () async {
    final bad = await post('{not json');
    expect(bad.statusCode, 400);
    expect(((await jsonOf(bad))['error'] as Map)['code'], 'invalid_json');

    final invalid = await post({'site': 'arm', 'photos': <Object?>[]});
    expect(invalid.statusCode, 400);
    final error = (await jsonOf(invalid))['error'] as Map;
    expect(error['code'], 'invalid_request');
    expect(error['message'], contains('photo'));
    expect(analyzer.calls, 0);
  });

  test('rate limits per install with Retry-After', () async {
    api = build(installBurst: 2);
    expect((await post(validBody())).statusCode, 200);
    expect((await post(validBody())).statusCode, 200);
    final limited = await post(validBody());
    expect(limited.statusCode, 429);
    expect(int.parse(limited.headers['retry-after']!), greaterThan(0));
    expect(analyzer.calls, 2);
  });

  test('rejects oversized bodies', () async {
    final r = await api.handler(
      Request(
        'POST',
        Uri.parse('http://localhost/v1/checks'),
        body: 'x' * (SpotCheckApi.maxBodyBytes + 1),
        headers: {'x-install-id': installId},
      ),
    );
    expect(r.statusCode, 413);
  });

  test('maps transient upstream failures to 503', () async {
    analyzer.behavior = (_) async => throw AnalysisFailed(
      'x',
      cause: ClaudeApiException(529, 'overloaded_error', 'Overloaded'),
    );
    final r = await post(validBody());
    expect(r.statusCode, 503);
    expect(r.headers['retry-after'], isNotNull);
  });

  test('maps other failures to 502', () async {
    analyzer.behavior = (_) async => throw AnalysisFailed('x');
    final r = await post(validBody());
    expect(r.statusCode, 502);
    expect(((await jsonOf(r))['error'] as Map)['code'], 'analysis_failed');
  });

  test('sheds load when the queue is full', () async {
    final gate = Completer<void>();
    analyzer.behavior = (request) async {
      await gate.future;
      return demo(request);
    };
    api = build(
      concurrency: ConcurrencyLimiter(maxConcurrent: 1, maxQueued: 0),
    );
    final first = post(validBody());
    await Future<void>.delayed(Duration.zero);
    final second = await post(validBody());
    expect(second.statusCode, 503);
    gate.complete();
    expect((await first).statusCode, 200);
  });

  test('times out slow analyses with 504', () async {
    analyzer.behavior = (_) => Completer<Analysis>().future;
    api = build(timeout: const Duration(milliseconds: 50));
    final r = await post(validBody());
    expect(r.statusCode, 504);
    expect(((await jsonOf(r))['error'] as Map)['code'], 'timeout');
  });

  test('never logs health information', () async {
    const secret = 'my private note about a rash';
    await post(validBody(note: secret));
    final logged = jsonEncode(logs);
    expect(logs.single['event'], 'check');
    expect(logged, isNot(contains(secret)));
    expect(logged, isNot(contains('Eczema')));
    expect(logged, isNot(contains('skin_kind')));
  });

  group('CORS', () {
    test('answers preflight for allowed origins', () async {
      api = build(cors: ['https://app.spotcheck.health']);
      final r = await api.handler(
        Request(
          'OPTIONS',
          Uri.parse('http://localhost/v1/checks'),
          headers: {'origin': 'https://app.spotcheck.health'},
        ),
      );
      expect(r.statusCode, 204);
      expect(
        r.headers['access-control-allow-origin'],
        'https://app.spotcheck.health',
      );
      expect(
        r.headers['access-control-allow-headers'],
        contains('x-install-id'),
      );
    });

    test('refuses other origins', () async {
      api = build(cors: ['https://app.spotcheck.health']);
      final r = await api.handler(
        Request(
          'OPTIONS',
          Uri.parse('http://localhost/v1/checks'),
          headers: {'origin': 'https://evil.example'},
        ),
      );
      expect(r.statusCode, 403);
      expect(r.headers['access-control-allow-origin'], isNull);
    });
  });
}
