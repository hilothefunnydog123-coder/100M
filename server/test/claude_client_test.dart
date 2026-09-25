import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotcheck_server/spotcheck_server.dart';
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
  'id': 'msg_1',
  'model': 'claude-opus-5-5',
  'stop_reason': 'end_turn',
  'content': [
    {'type': 'thinking', 'thinking': '', 'signature': 'x'},
    {'type': 'text', 'text': '{"a":'},
    {'type': 'text', 'text': '1}'},
  ],
  'usage': {'input_tokens': 10, 'output_tokens': 5},
};

void main() {
  test('sends the documented headers and parses the response', () async {
    late http.Request seen;
    final client = ClaudeClient(
      apiKey: 'sk-test',
      httpClient: MockClient((request) async {
        seen = request;
        return jsonResponse(200, okBody);
      }),
    );
    final message = await client.createMessage(
      {'model': 'claude-opus-5-5'},
      betas: ['server-side-fallback-2026-07-01'],
    );

    expect(seen.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(seen.headers['x-api-key'], 'sk-test');
    expect(seen.headers['anthropic-version'], '2023-06-01');
    expect(seen.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
    expect(seen.headers['content-type'], startsWith('application/json'));
    expect(message.text, '{"a":1}');
    expect(message.stopReason, 'end_turn');
    expect(message.inputTokens, 10);
    expect(message.refused, isFalse);
  });

  test('omits the beta header when there are no betas', () async {
    late http.Request seen;
    final client = ClaudeClient(
      apiKey: 'k',
      httpClient: MockClient((request) async {
        seen = request;
        return jsonResponse(200, okBody);
      }),
    );
    await client.createMessage({});
    expect(seen.headers.containsKey('anthropic-beta'), isFalse);
  });

  test('retries overloaded responses, honoring retry-after', () async {
    var calls = 0;
    final sleeps = <Duration>[];
    final client = ClaudeClient(
      apiKey: 'k',
      sleep: (d) async => sleeps.add(d),
      httpClient: MockClient((request) async {
        calls++;
        if (calls == 1) {
          return jsonResponse(
            529,
            {
              'type': 'error',
              'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
            },
            headers: {'retry-after': '3'},
          );
        }
        return jsonResponse(200, okBody);
      }),
    );
    final message = await client.createMessage({});
    expect(message.id, 'msg_1');
    expect(calls, 2);
    expect(sleeps, [const Duration(seconds: 3)]);
  });

  test('gives up after maxRetries transient failures', () async {
    var calls = 0;
    final client = ClaudeClient(
      apiKey: 'k',
      maxRetries: 2,
      sleep: (_) async {},
      httpClient: MockClient((request) async {
        calls++;
        return jsonResponse(429, {
          'type': 'error',
          'error': {'type': 'rate_limit_error', 'message': 'Slow down'},
        });
      }),
    );
    await expectLater(
      client.createMessage({}),
      throwsA(
        isA<ClaudeApiException>()
            .having((e) => e.statusCode, 'status', 429)
            .having((e) => e.isTransient, 'transient', isTrue),
      ),
    );
    expect(calls, 3);
  });

  test('does not retry client errors and reports the request id', () async {
    var calls = 0;
    final client = ClaudeClient(
      apiKey: 'k',
      sleep: (_) async {},
      httpClient: MockClient((request) async {
        calls++;
        return jsonResponse(
          400,
          {
            'type': 'error',
            'error': {'type': 'invalid_request_error', 'message': 'bad field'},
          },
          headers: {'request-id': 'req_42'},
        );
      }),
    );
    await expectLater(
      client.createMessage({}),
      throwsA(
        isA<ClaudeApiException>()
            .having((e) => e.type, 'type', 'invalid_request_error')
            .having((e) => e.message, 'message', 'bad field')
            .having((e) => e.requestId, 'requestId', 'req_42')
            .having((e) => e.isTransient, 'transient', isFalse),
      ),
    );
    expect(calls, 1);
  });

  test('tolerates non-JSON error bodies', () async {
    final client = ClaudeClient(
      apiKey: 'k',
      maxRetries: 0,
      httpClient: MockClient((_) async => http.Response('<html>', 502)),
    );
    await expectLater(
      client.createMessage({}),
      throwsA(
        isA<ClaudeApiException>().having((e) => e.statusCode, 'status', 502),
      ),
    );
  });

  test('retries connection errors', () async {
    var calls = 0;
    final client = ClaudeClient(
      apiKey: 'k',
      sleep: (_) async {},
      httpClient: MockClient((request) async {
        calls++;
        if (calls == 1) throw http.ClientException('reset');
        return jsonResponse(200, okBody);
      }),
    );
    expect((await client.createMessage({})).id, 'msg_1');
    expect(calls, 2);
  });

  test('refusals are detected from the stop reason', () {
    final m = ClaudeMessage({
      'stop_reason': 'refusal',
      'stop_details': {'type': 'refusal', 'category': 'bio'},
      'content': <Object?>[],
    });
    expect(m.refused, isTrue);
    expect(m.text, isEmpty);
    expect(m.stopDetails!['category'], 'bio');
  });
}
