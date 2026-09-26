import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'model_api.dart';

/// The subset of the Gemini API the Gemini drafter needs. Implemented by
/// [GeminiClient] and by fakes in tests.
abstract interface class GenerateContentApi {
  Future<GeminiResponse> generateContent(
    String model,
    Map<String, Object?> body,
  );
}

/// A parsed `generateContent` response.
class GeminiResponse {
  GeminiResponse(this.json);

  final Map<String, Object?> json;

  String get responseId => json['responseId'] as String? ?? '';

  Map<String, Object?> get _candidate => switch (json['candidates']) {
    [final Map<String, Object?> first, ...] => first,
    _ => const {},
  };

  /// `STOP`, `MAX_TOKENS`, `SAFETY`... Empty when the prompt was blocked.
  String get finishReason => _candidate['finishReason'] as String? ?? '';

  /// Set when the request itself was blocked; there are no candidates then.
  String? get blockReason => switch (json['promptFeedback']) {
    {'blockReason': final String reason} => reason,
    _ => null,
  };

  /// Declined by Google's safety filters, before or while answering.
  bool get blocked =>
      blockReason != null || _blockingReasons.contains(finishReason);

  static const _blockingReasons = {
    'SAFETY',
    'BLOCKLIST',
    'PROHIBITED_CONTENT',
    'SPII',
    'IMAGE_SAFETY',
    'IMAGE_PROHIBITED_CONTENT',
  };

  /// The answer's text parts, joined. Thought summaries are skipped.
  String get text => switch (_candidate['content']) {
    {'parts': final List<Object?> parts} => [
      for (final part in parts)
        if (part is Map && part['thought'] != true && part['text'] is String)
          part['text'] as String,
    ].join(),
    _ => '',
  };

  Map<String, Object?> get usage =>
      json['usageMetadata'] as Map<String, Object?>? ?? const {};

  int _usage(String key) => (usage[key] as num?)?.toInt() ?? 0;

  /// All input tokens, [cachedTokens] included.
  int get promptTokens => _usage('promptTokenCount');
  int get cachedTokens => _usage('cachedContentTokenCount');

  /// The answer, without [thoughtTokens]. Both are billed as output.
  int get answerTokens => _usage('candidatesTokenCount');
  int get thoughtTokens => _usage('thoughtsTokenCount');
}

class GeminiApiException implements ModelApiException {
  GeminiApiException(
    this.statusCode,
    this.type,
    this.message, {
    this.retryDelay,
    this.dailyQuota = false,
  });

  @override
  final int statusCode;

  /// Google's status, such as `RESOURCE_EXHAUSTED` or `INVALID_ARGUMENT`.
  @override
  final String type;
  final String message;

  /// How long Google asks callers to wait, when it says.
  final Duration? retryDelay;

  /// A per-day quota ran out (the free tier's daily requests). It resets
  /// at midnight Pacific time, so retrying sooner can't help.
  final bool dailyQuota;

  @override
  String? get requestId => null;

  @override
  bool get isTransient =>
      !dailyQuota &&
      (statusCode == 408 ||
          statusCode == 429 ||
          statusCode == 500 ||
          statusCode == 502 ||
          statusCode == 503 ||
          statusCode == 504);

  @override
  String toString() => 'GeminiApiException($statusCode $type: $message)';
}

/// A minimal raw-HTTP client for `POST /v1beta/models/<model>:generateContent`,
/// with the same retry policy as [ClaudeClient]: 408/429/5xx are retried,
/// honoring the delay Google asks for, except when a daily quota ran out.
class GeminiClient implements GenerateContentApi {
  GeminiClient({
    required this.apiKey,
    http.Client? httpClient,
    Uri? baseUrl,
    this.maxRetries = 2,
    this.timeout = const Duration(seconds: 150),
    Future<void> Function(Duration)? sleep,
  }) : _http = httpClient ?? http.Client(),
       _baseUrl =
           baseUrl ?? Uri.parse('https://generativelanguage.googleapis.com'),
       _sleep = sleep ?? Future<void>.delayed;

  final String apiKey;
  final int maxRetries;
  final Duration timeout;
  final http.Client _http;
  final Uri _baseUrl;
  final Future<void> Function(Duration) _sleep;
  final _random = Random();

  @override
  Future<GeminiResponse> generateContent(
    String model,
    Map<String, Object?> body,
  ) async {
    // Append to any path prefix (e.g. a proxy mounted at /gemini).
    final prefix = _baseUrl.path.replaceAll(RegExp(r'/+$'), '');
    final uri = _baseUrl.replace(
      path: '$prefix/v1beta/models/$model:generateContent',
    );
    final headers = {
      'content-type': 'application/json',
      'x-goog-api-key': apiKey,
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
          throw GeminiApiException(408, 'DEADLINE_EXCEEDED', 'Timed out.');
        }
        await _sleep(_backoff(attempt, null));
        continue;
      } on SocketException catch (e) {
        if (attempt >= maxRetries) {
          throw GeminiApiException(503, 'UNAVAILABLE', e.message);
        }
        await _sleep(_backoff(attempt, null));
        continue;
      } on http.ClientException catch (e) {
        if (attempt >= maxRetries) {
          throw GeminiApiException(503, 'UNAVAILABLE', e.message);
        }
        await _sleep(_backoff(attempt, null));
        continue;
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map<String, Object?>) {
          throw GeminiApiException(502, 'BAD_RESPONSE', 'Unexpected body.');
        }
        return GeminiResponse(decoded);
      }

      final error = _parseError(response);
      if (error.isTransient && attempt < maxRetries) {
        final header = double.tryParse(response.headers['retry-after'] ?? '');
        await _sleep(
          _backoff(
            attempt,
            header == null
                ? error.retryDelay
                : Duration(milliseconds: (header * 1000).round()),
          ),
        );
        continue;
      }
      throw error;
    }
  }

  Duration _backoff(int attempt, Duration? asked) {
    if (asked != null && asked <= const Duration(seconds: 60)) return asked;
    final base = 500 * pow(2, attempt);
    return Duration(milliseconds: (base + _random.nextInt(250)).toInt());
  }

  GeminiApiException _parseError(http.Response response) {
    var status = 'UNKNOWN';
    var message = 'HTTP ${response.statusCode}';
    Duration? retryDelay;
    var dailyQuota = false;
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body case {'error': final Map<String, Object?> err}) {
        if (err['status'] case final String s) status = s;
        if (err['message'] case final String m) message = m;
        for (final detail in err['details'] as List? ?? const []) {
          if (detail case {'retryDelay': final String delay}) {
            final seconds = double.tryParse(delay.replaceAll('s', ''));
            if (seconds != null) {
              retryDelay = Duration(milliseconds: (seconds * 1000).round());
            }
          }
          if (detail case {'violations': final List<Object?> violations}) {
            for (final v in violations) {
              if (v case {
                'quotaId': final String id,
              } when id.contains('PerDay')) {
                dailyQuota = true;
              }
            }
          }
        }
      }
    } on FormatException {
      // Non-JSON error body (e.g. from a proxy); keep the defaults.
    }
    return GeminiApiException(
      response.statusCode,
      status,
      message,
      retryDelay: retryDelay,
      dailyQuota: dailyQuota,
    );
  }

  void close() => _http.close();
}
