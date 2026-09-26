import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'model_api.dart';

/// The subset of an OpenAI-compatible chat completions API the Groq drafter
/// needs. Implemented by [GroqClient] and by fakes in tests.
abstract interface class ChatCompletionsApi {
  Future<ChatCompletion> createChatCompletion(Map<String, Object?> body);
}

/// A parsed chat completion.
class ChatCompletion {
  ChatCompletion(this.json);

  final Map<String, Object?> json;

  String get id => json['id'] as String? ?? '';

  String get model => json['model'] as String? ?? '';

  Map<String, Object?> get _choice => switch (json['choices']) {
    [final Map<String, Object?> first, ...] => first,
    _ => const {},
  };

  /// `stop`, `length` (hit `max_completion_tokens`), `content_filter`...
  String get finishReason => _choice['finish_reason'] as String? ?? '';

  /// The answer. Reasoning, when it is returned at all, is a separate field.
  String get content => switch (_choice['message']) {
    {'content': final String text} => text,
    _ => '',
  };

  Map<String, Object?> get usage =>
      json['usage'] as Map<String, Object?>? ?? const {};

  /// All input tokens, [cachedTokens] included.
  int get promptTokens => (usage['prompt_tokens'] as num?)?.toInt() ?? 0;

  /// Reasoning plus the answer.
  int get completionTokens =>
      (usage['completion_tokens'] as num?)?.toInt() ?? 0;

  int get cachedTokens => switch (usage['prompt_tokens_details']) {
    {'cached_tokens': final num n} => n.toInt(),
    _ => 0,
  };
}

class GroqApiException implements ModelApiException {
  GroqApiException(
    this.statusCode,
    this.type,
    this.message, {
    this.code = '',
    this.requestId,
  });

  @override
  final int statusCode;
  @override
  final String type;

  /// Groq's error code, such as `rate_limit_exceeded` or
  /// `json_validate_failed`.
  final String code;
  final String message;
  @override
  final String? requestId;

  /// Rate limited, over capacity (498), or a transient server error.
  @override
  bool get isTransient =>
      statusCode == 408 ||
      statusCode == 429 ||
      statusCode == 498 ||
      statusCode >= 500;

  /// JSON mode rejected the model's output as invalid JSON. The same
  /// request can work on a second try.
  bool get invalidJson => code == 'json_validate_failed';

  /// The prompt plus `max_completion_tokens` is more than the account's
  /// per-minute token limit. Retrying can't help; the request has to shrink.
  bool get tooLarge => statusCode == 413;

  @override
  String toString() =>
      'GroqApiException($statusCode ${code.isEmpty ? type : code}: $message'
      '${requestId == null ? '' : ', request $requestId'})';
}

/// A minimal raw-HTTP client for Groq's OpenAI-compatible
/// `POST /openai/v1/chat/completions`: a bearer key, and retries on
/// 408/429/498/5xx with `retry-after` honored, like [ClaudeClient].
class GroqClient implements ChatCompletionsApi {
  GroqClient({
    required this.apiKey,
    http.Client? httpClient,
    Uri? baseUrl,
    this.maxRetries = 2,
    this.timeout = const Duration(seconds: 150),
    Future<void> Function(Duration)? sleep,
  }) : _http = httpClient ?? http.Client(),
       _baseUrl = baseUrl ?? Uri.parse('https://api.groq.com'),
       _sleep = sleep ?? Future<void>.delayed;

  final String apiKey;
  final int maxRetries;
  final Duration timeout;
  final http.Client _http;
  final Uri _baseUrl;
  final Future<void> Function(Duration) _sleep;
  final _random = Random();

  @override
  Future<ChatCompletion> createChatCompletion(Map<String, Object?> body) async {
    // Append to any path prefix (e.g. a proxy mounted at /groq).
    final prefix = _baseUrl.path.replaceAll(RegExp(r'/+$'), '');
    final uri = _baseUrl.replace(path: '$prefix/openai/v1/chat/completions');
    final headers = {
      'content-type': 'application/json',
      'authorization': 'Bearer $apiKey',
    };
    final encoded = jsonEncode(body);

    for (var attempt = 0; ; attempt++) {
      http.Response response;
      try {
        response = await _http
            .post(uri, headers: headers, body: encoded)
            .timeout(timeout);
      } on TimeoutException {
        if (attempt >= maxRetries) {
          throw GroqApiException(408, 'timeout', 'Request timed out.');
        }
        await _sleep(_backoff(attempt, null));
        continue;
      } on SocketException catch (e) {
        if (attempt >= maxRetries) {
          throw GroqApiException(503, 'connection_error', e.message);
        }
        await _sleep(_backoff(attempt, null));
        continue;
      } on http.ClientException catch (e) {
        if (attempt >= maxRetries) {
          throw GroqApiException(503, 'connection_error', e.message);
        }
        await _sleep(_backoff(attempt, null));
        continue;
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map<String, Object?>) {
          throw GroqApiException(502, 'bad_response', 'Unexpected body.');
        }
        return ChatCompletion(decoded);
      }

      final error = _parseError(response);
      if (error.isTransient && attempt < maxRetries) {
        await _sleep(_backoff(attempt, response.headers['retry-after']));
        continue;
      }
      throw error;
    }
  }

  Duration _backoff(int attempt, String? retryAfter) {
    final seconds = double.tryParse(retryAfter ?? '');
    if (seconds != null && seconds >= 0 && seconds <= 60) {
      return Duration(milliseconds: (seconds * 1000).round());
    }
    final base = 500 * pow(2, attempt);
    return Duration(milliseconds: (base + _random.nextInt(250)).toInt());
  }

  GroqApiException _parseError(http.Response response) {
    var type = 'api_error';
    var code = '';
    var message = 'HTTP ${response.statusCode}';
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body case {'error': final Map<String, Object?> err}) {
        if (err['type'] case final String t) type = t;
        if (err['code'] case final String c) code = c;
        if (err['message'] case final String m) message = m;
      }
    } on FormatException {
      // Non-JSON error body (e.g. from a proxy); keep the defaults.
    }
    return GroqApiException(
      response.statusCode,
      type,
      message,
      code: code,
      requestId: response.headers['x-request-id'],
    );
  }

  void close() => _http.close();
}
