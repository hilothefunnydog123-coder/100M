import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

http.Response jsonResponse(
  int status,
  Object body, {
  Map<String, String> headers = const {},
}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

final okBody = {
  'id': 'chatcmpl-1',
  'object': 'chat.completion',
  'model': 'qwen/qwen3.8-27b',
  'choices': [
    {
      'index': 0,
      'message': {'role': 'assistant', 'content': '{"a":1}'},
      'finish_reason': 'stop',
    },
  ],
  'usage': {
    'prompt_tokens': 5000,
    'completion_tokens': 1200,
    'prompt_tokens_details': {'cached_tokens': 1000},
  },
};

Map<String, Object?> errorBody(String type, String message, {String? code}) => {
  'error': {'type': type, 'message': message, 'code': ?code},
};

void main() {
  test('sends a bearer key to the OpenAI-compatible path', () async {
    late http.Request seen;
    final client = GroqClient(
      apiKey: 'gsk-test',
      httpClient: MockClient((request) async {
        seen = request;
        return jsonResponse(200, okBody);
      }),
    );
    final completion = await client.createChatCompletion({
      'model': 'qwen/qwen3.8-27b',
    });

    expect(
      seen.url.toString(),
      'https://api.groq.com/openai/v1/chat/completions',
    );
    expect(seen.headers['authorization'], 'Bearer gsk-test');
    expect(seen.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(seen.body), {'model': 'qwen/qwen3.8-27b'});
    expect(completion.id, 'chatcmpl-1');
    expect(completion.model, 'qwen/qwen3.8-27b');
    expect(completion.content, '{"a":1}');
    expect(completion.finishReason, 'stop');
    expect(completion.promptTokens, 5000);
    expect(completion.completionTokens, 1200);
    expect(completion.cachedTokens, 1000);
  });

  test('keeps a base URL path prefix', () async {
    late Uri seen;
    final client = GroqClient(
      apiKey: 'k',
      baseUrl: Uri.parse('https://proxy.example/groq/'),
      httpClient: MockClient((request) async {
        seen = request.url;
        return jsonResponse(200, okBody);
      }),
    );
    await client.createChatCompletion({});
    expect(
      seen.toString(),
      'https://proxy.example/groq/openai/v1/chat/completions',
    );
  });

  test('retries rate limits, honoring retry-after', () async {
    var calls = 0;
    final sleeps = <Duration>[];
    final client = GroqClient(
      apiKey: 'k',
      sleep: (d) async => sleeps.add(d),
      httpClient: MockClient((request) async {
        calls++;
        if (calls == 1) {
          return jsonResponse(
            429,
            errorBody(
              'tokens',
              'Rate limit reached. Please try again in 7.5s.',
              code: 'rate_limit_exceeded',
            ),
            headers: {'retry-after': '7.5'},
          );
        }
        return jsonResponse(200, okBody);
      }),
    );
    expect((await client.createChatCompletion({})).id, 'chatcmpl-1');
    expect(calls, 2);
    expect(sleeps, [const Duration(milliseconds: 7500)]);
  });

  test('gives up after maxRetries transient failures', () async {
    var calls = 0;
    final client = GroqClient(
      apiKey: 'k',
      maxRetries: 2,
      sleep: (_) async {},
      httpClient: MockClient((request) async {
        calls++;
        return jsonResponse(503, errorBody('api_error', 'Unavailable'));
      }),
    );
    await expectLater(
      client.createChatCompletion({}),
      throwsA(
        isA<GroqApiException>()
            .having((e) => e.statusCode, 'status', 503)
            .having((e) => e.isTransient, 'transient', isTrue),
      ),
    );
    expect(calls, 3);
  });

  test('a request over the per-minute token limit is not retried', () async {
    var calls = 0;
    final client = GroqClient(
      apiKey: 'k',
      sleep: (_) async {},
      httpClient: MockClient((request) async {
        calls++;
        return jsonResponse(
          413,
          errorBody(
            'tokens',
            'Request too large for model `qwen/qwen3.8-27b` on tokens per '
                'minute (TPM): Limit 8000, Requested 9480.',
            code: 'rate_limit_exceeded',
          ),
          headers: {'x-request-id': 'req_413'},
        );
      }),
    );
    await expectLater(
      client.createChatCompletion({}),
      throwsA(
        isA<GroqApiException>()
            .having((e) => e.tooLarge, 'tooLarge', isTrue)
            .having((e) => e.isTransient, 'transient', isFalse)
            .having((e) => e.requestId, 'requestId', 'req_413')
            .having((e) => e.message, 'message', contains('Limit 8000')),
      ),
    );
    expect(calls, 1);
  });

  test('reads error codes, such as invalid JSON from JSON mode', () async {
    final client = GroqClient(
      apiKey: 'k',
      httpClient: MockClient(
        (_) async => jsonResponse(
          400,
          errorBody(
            'invalid_request_error',
            'Failed to generate JSON.',
            code: 'json_validate_failed',
          ),
        ),
      ),
    );
    await expectLater(
      client.createChatCompletion({}),
      throwsA(
        isA<GroqApiException>()
            .having((e) => e.invalidJson, 'invalidJson', isTrue)
            .having((e) => e.isTransient, 'transient', isFalse)
            .having((e) => '$e', 'toString', contains('json_validate_failed')),
      ),
    );
  });

  test('tolerates non-JSON error bodies and odd shapes', () async {
    final client = GroqClient(
      apiKey: 'k',
      maxRetries: 0,
      httpClient: MockClient((_) async => http.Response('<html>', 502)),
    );
    await expectLater(
      client.createChatCompletion({}),
      throwsA(
        isA<GroqApiException>().having((e) => e.statusCode, 'status', 502),
      ),
    );
    final empty = ChatCompletion({'choices': <Object?>[]});
    expect(empty.content, '');
    expect(empty.finishReason, '');
    expect(empty.promptTokens, 0);
  });

  test('retries connection errors', () async {
    var calls = 0;
    final client = GroqClient(
      apiKey: 'k',
      sleep: (_) async {},
      httpClient: MockClient((request) async {
        calls++;
        if (calls == 1) throw http.ClientException('reset');
        return jsonResponse(200, okBody);
      }),
    );
    expect((await client.createChatCompletion({})).id, 'chatcmpl-1');
    expect(calls, 2);
  });
}
