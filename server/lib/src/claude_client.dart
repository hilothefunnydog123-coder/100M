import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

/// The subset of the Claude Messages API the drafter needs. Implemented by
/// [ClaudeClient] and by fakes in tests and local development.
abstract interface class MessagesApi {
  Future<ClaudeMessage> createMessage(
    Map<String, Object?> body, {
    List<String> betas,
  });
}

/// A parsed Messages API response.
class ClaudeMessage {
  ClaudeMessage(this.json);

  final Map<String, Object?> json;

  String get id => json['id'] as String? ?? '';

  /// The model that produced the message. With server-side fallbacks this
  /// can differ from the model that was requested.
  String get model => json['model'] as String? ?? '';

  String get stopReason => json['stop_reason'] as String? ?? '';

  bool get refused => stopReason == 'refusal';

  /// Only set on refusals; informational.
  Map<String, Object?>? get stopDetails =>
      json['stop_details'] as Map<String, Object?>?;

  List<Map<String, Object?>> get content => [
    for (final block in (json['content'] as List? ?? const []))
      if (block is Map<String, Object?>) block,
  ];

  /// Concatenated `text` blocks. Thinking and fallback blocks are skipped:
  /// responses are read by block type, never by position.
  String get text => [
    for (final block in content)
      if (block['type'] == 'text') block['text'] as String? ?? '',
  ].join();

  Map<String, Object?> get usage =>
      json['usage'] as Map<String, Object?>? ?? const {};

  int _usage(String key) => (usage[key] as num?)?.toInt() ?? 0;

  int get inputTokens => _usage('input_tokens');
  int get outputTokens => _usage('output_tokens');
  int get cacheReadTokens => _usage('cache_read_input_tokens');
  int get cacheWriteTokens => _usage('cache_creation_input_tokens');
}

class ClaudeApiException implements Exception {
  ClaudeApiException(
    this.statusCode,
    this.type,
    this.message, {
    this.requestId,
  });

  final int statusCode;
  final String type;
  final String message;
  final String? requestId;

  /// Overloaded, rate limited, or a transient server error.
  bool get isTransient =>
      statusCode == 408 ||
      statusCode == 409 ||
      statusCode == 429 ||
      statusCode >= 500;

  @override
  String toString() =>
      'ClaudeApiException($statusCode $type: $message'
      '${requestId == null ? '' : ', request $requestId'})';
}

/// A minimal raw-HTTP client for `POST /v1/messages`.
///
/// Dart has no official Anthropic SDK, so this follows the documented REST
/// contract: `x-api-key` and `anthropic-version` headers, betas in
/// `anthropic-beta`, retries on 408/409/429/5xx with `retry-after` honored.
class ClaudeClient implements MessagesApi {
  ClaudeClient({
    required this.apiKey,
    http.Client? httpClient,
    Uri? baseUrl,
    this.maxRetries = 2,
    this.timeout = const Duration(seconds: 150),
    Future<void> Function(Duration)? sleep,
  }) : _http = httpClient ?? http.Client(),
       _baseUrl = baseUrl ?? Uri.parse('https://api.anthropic.com'),
       _sleep = sleep ?? Future<void>.delayed;

  static const apiVersion = '2023-06-01';

  final String apiKey;
  final int maxRetries;
  final Duration timeout;
  final http.Client _http;
  final Uri _baseUrl;
  final Future<void> Function(Duration) _sleep;
  final _random = Random();

  @override
  Future<ClaudeMessage> createMessage(
    Map<String, Object?> body, {
    List<String> betas = const [],
  }) async {
    // Append to any path prefix (e.g. a proxy mounted at /anthropic).
    final prefix = _baseUrl.path.replaceAll(RegExp(r'/+$'), '');
    final uri = _baseUrl.replace(path: '$prefix/v1/messages');
    final headers = {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': apiVersion,
      if (betas.isNotEmpty) 'anthropic-beta': betas.join(','),
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
          throw ClaudeApiException(408, 'timeout', 'Request timed out.');
        }
        await _sleep(_backoff(attempt, null));
        continue;
      } on SocketException catch (e) {
        if (attempt >= maxRetries) {
          throw ClaudeApiException(503, 'connection_error', e.message);
        }
        await _sleep(_backoff(attempt, null));
        continue;
      } on http.ClientException catch (e) {
        if (attempt >= maxRetries) {
          throw ClaudeApiException(503, 'connection_error', e.message);
        }
        await _sleep(_backoff(attempt, null));
        continue;
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map<String, Object?>) {
          throw ClaudeApiException(502, 'bad_response', 'Unexpected body.');
        }
        return ClaudeMessage(decoded);
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

  ClaudeApiException _parseError(http.Response response) {
    var type = 'api_error';
    var message = 'HTTP ${response.statusCode}';
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['error'] is Map) {
        final err = body['error'] as Map;
        type = err['type'] as String? ?? type;
        message = err['message'] as String? ?? message;
      }
    } on FormatException {
      // Non-JSON error body (e.g. from a proxy); keep the defaults.
    }
    return ClaudeApiException(
      response.statusCode,
      type,
      message,
      requestId: response.headers['request-id'],
    );
  }

  void close() => _http.close();
}
