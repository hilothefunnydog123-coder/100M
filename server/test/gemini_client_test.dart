import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

http.Response jsonResponse(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

final okBody = {
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {'text': 'thinking it over', 'thought': true},
          {'text': '{"a":', 'thoughtSignature': 'sig'},
          {'text': '1}'},
        ],
      },
      'finishReason': 'STOP',
    },
  ],
  'usageMetadata': {
    'promptTokenCount': 5000,
    'candidatesTokenCount': 900,
    'thoughtsTokenCount': 2100,
    'cachedContentTokenCount': 1000,
  },
  'responseId': 'resp_1',
};

/// Google's error shape, with the retry and quota details it attaches to
/// rate-limit errors.
Map<String, Object?> errorBody(
  int code,
  String status,
  String message, {
  String? retryDelay,
  String? quotaId,
}) => {
  'error': {
    'code': code,
    'status': status,
    'message': message,
    'details': [
      if (quotaId != null)
        {
          '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
          'violations': [
            {
              'quotaMetric':
                  'generativelanguage.googleapis.com/generate_content_free_tier_requests',
              'quotaId': quotaId,
            },
          ],
        },
      if (retryDelay != null)
        {
          '@type': 'type.googleapis.com/google.rpc.RetryInfo',
          'retryDelay': retryDelay,
        },
    ],
  },
};

void main() {
  test('sends the key in a header to the model path', () async {
    late http.Request seen;
    final client = GeminiClient(
      apiKey: 'AIza-test',
      httpClient: MockClient((request) async {
        seen = request;
        return jsonResponse(200, okBody);
      }),
    );
    final response = await client.generateContent('gemini-3.8-flash', {
      'contents': <Object?>[],
    });

    expect(
      seen.url.toString(),
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-3.8-flash:generateContent',
    );
    expect(seen.headers['x-goog-api-key'], 'AIza-test');
    expect(seen.url.queryParameters, isEmpty);
    expect(jsonDecode(seen.body), {'contents': <Object?>[]});
    expect(response.text, '{"a":1}');
    expect(response.finishReason, 'STOP');
    expect(response.blocked, isFalse);
    expect(response.promptTokens, 5000);
    expect(response.cachedTokens, 1000);
    expect(response.answerTokens, 900);
    expect(response.thoughtTokens, 2100);
  });

  test('keeps a base URL path prefix', () async {
    late Uri seen;
    final client = GeminiClient(
      apiKey: 'k',
      baseUrl: Uri.parse('https://proxy.example/gemini/'),
      httpClient: MockClient((request) async {
        seen = request.url;
        return jsonResponse(200, okBody);
      }),
    );
    await client.generateContent('gemini-3.8-flash', {});
    expect(
      seen.toString(),
      'https://proxy.example/gemini/v1beta/models/'
      'gemini-3.8-flash:generateContent',
    );
  });

  test('retries rate limits after the delay Google asks for', () async {
    var calls = 0;
    final sleeps = <Duration>[];
    final client = GeminiClient(
      apiKey: 'k',
      sleep: (d) async => sleeps.add(d),
      httpClient: MockClient((request) async {
        calls++;
        if (calls == 1) {
          return jsonResponse(
            429,
            errorBody(
              429,
              'RESOURCE_EXHAUSTED',
              'Quota exceeded.',
              retryDelay: '12.5s',
              quotaId: 'GenerateRequestsPerMinutePerProjectPerModel-FreeTier',
            ),
          );
        }
        return jsonResponse(200, okBody);
      }),
    );
    expect((await client.generateContent('m', {})).responseId, 'resp_1');
    expect(calls, 2);
    expect(sleeps, [const Duration(milliseconds: 12500)]);
  });

  test('waits longer between retries when asked to', () async {
    var calls = 0;
    final sleeps = <Duration>[];
    final client = GeminiClient(
      apiKey: 'k',
      retryBase: const Duration(seconds: 20),
      sleep: (d) async => sleeps.add(d),
      httpClient: MockClient((request) async {
        calls++;
        if (calls < 3) {
          return jsonResponse(
            503,
            errorBody(503, 'UNAVAILABLE', 'The model is overloaded.'),
          );
        }
        return jsonResponse(200, okBody);
      }),
    );
    expect((await client.generateContent('m', {})).responseId, 'resp_1');
    expect(sleeps, hasLength(2));
    expect(sleeps[0].inMilliseconds, inInclusiveRange(20000, 20250));
    expect(sleeps[1].inMilliseconds, inInclusiveRange(40000, 40250));
  });

  test('a spent daily quota is not retried', () async {
    var calls = 0;
    final client = GeminiClient(
      apiKey: 'k',
      sleep: (_) async {},
      httpClient: MockClient((request) async {
        calls++;
        return jsonResponse(
          429,
          errorBody(
            429,
            'RESOURCE_EXHAUSTED',
            'You exceeded your current quota.',
            retryDelay: '30s',
            quotaId: 'GenerateRequestsPerDayPerProjectPerModel-FreeTier',
          ),
        );
      }),
    );
    await expectLater(
      client.generateContent('m', {}),
      throwsA(
        isA<GeminiApiException>()
            .having((e) => e.dailyQuota, 'dailyQuota', isTrue)
            .having((e) => e.isTransient, 'transient', isFalse)
            .having((e) => e.type, 'type', 'RESOURCE_EXHAUSTED'),
      ),
    );
    expect(calls, 1);
  });

  test('gives up after maxRetries transient failures', () async {
    var calls = 0;
    final client = GeminiClient(
      apiKey: 'k',
      maxRetries: 2,
      sleep: (_) async {},
      httpClient: MockClient((request) async {
        calls++;
        return jsonResponse(
          503,
          errorBody(503, 'UNAVAILABLE', 'The model is overloaded.'),
        );
      }),
    );
    await expectLater(
      client.generateContent('m', {}),
      throwsA(
        isA<GeminiApiException>()
            .having((e) => e.statusCode, 'status', 503)
            .having((e) => e.isTransient, 'transient', isTrue),
      ),
    );
    expect(calls, 3);
  });

  test('does not retry bad requests', () async {
    var calls = 0;
    final client = GeminiClient(
      apiKey: 'k',
      sleep: (_) async {},
      httpClient: MockClient((request) async {
        calls++;
        return jsonResponse(
          400,
          errorBody(400, 'INVALID_ARGUMENT', 'Invalid JSON payload.'),
        );
      }),
    );
    await expectLater(
      client.generateContent('m', {}),
      throwsA(
        isA<GeminiApiException>()
            .having((e) => e.message, 'message', 'Invalid JSON payload.')
            .having((e) => e.isTransient, 'transient', isFalse),
      ),
    );
    expect(calls, 1);
  });

  test('tolerates non-JSON error bodies', () async {
    final client = GeminiClient(
      apiKey: 'k',
      maxRetries: 0,
      httpClient: MockClient((_) async => http.Response('<html>', 502)),
    );
    await expectLater(
      client.generateContent('m', {}),
      throwsA(
        isA<GeminiApiException>().having((e) => e.statusCode, 'status', 502),
      ),
    );
  });

  test('retries connection errors', () async {
    var calls = 0;
    final client = GeminiClient(
      apiKey: 'k',
      sleep: (_) async {},
      httpClient: MockClient((request) async {
        calls++;
        if (calls == 1) throw http.ClientException('reset');
        return jsonResponse(200, okBody);
      }),
    );
    expect((await client.generateContent('m', {})).responseId, 'resp_1');
    expect(calls, 2);
  });

  test('blocks are read from the prompt feedback or the finish reason', () {
    expect(
      GeminiResponse({
        'promptFeedback': {'blockReason': 'PROHIBITED_CONTENT'},
      }).blocked,
      isTrue,
    );
    final safety = GeminiResponse({
      'candidates': [
        {'finishReason': 'SAFETY'},
      ],
    });
    expect(safety.blocked, isTrue);
    expect(safety.text, '');
    expect(
      GeminiResponse({
        'candidates': [
          {'finishReason': 'MAX_TOKENS'},
        ],
      }).blocked,
      isFalse,
    );
  });
}
