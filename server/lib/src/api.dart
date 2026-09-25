import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

import 'analyzer.dart';
import 'claude_client.dart';
import 'limits.dart';
import 'prompt.dart';

typedef LogSink = void Function(Map<String, Object?> event);

/// The HTTP API. Stateless: photos and answers are analyzed in memory and
/// never stored or logged.
class SpotCheckApi {
  SpotCheckApi({
    required CheckAnalyzer analyzer,
    required this.installLimiter,
    required this.ipLimiter,
    required this.concurrency,
    this.corsOrigins = const ['*'],
    this.model = '',
    this.analysisTimeout = const Duration(seconds: 170),
    LogSink? log,
  }) : _analyzer = analyzer,
       _log = log ?? _stdoutLog;

  /// Three photos at the per-photo cap, base64-encoded, plus JSON overhead.
  static const maxBodyBytes = 15 * 1024 * 1024;

  static final _installIdPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

  final CheckAnalyzer _analyzer;
  final RateLimiter installLimiter;
  final RateLimiter ipLimiter;
  final ConcurrencyLimiter concurrency;
  final List<String> corsOrigins;
  final String model;

  /// Upper bound on one analysis, so a phone never waits indefinitely.
  final Duration analysisTimeout;

  final LogSink _log;

  Handler get handler {
    final router = Router()
      ..get('/healthz', _health)
      ..post('/v1/checks', _createCheck);
    return const Pipeline()
        .addMiddleware(_cors())
        .addMiddleware(_securityHeaders)
        .addHandler(router.call);
  }

  Response _health(Request request) =>
      _json(200, {'ok': true, 'prompt_version': promptVersion, 'model': model});

  Future<Response> _createCheck(Request request) async {
    final watch = Stopwatch()..start();
    final installId = request.headers['x-install-id'] ?? '';
    if (!_installIdPattern.hasMatch(installId)) {
      return _error(
        400,
        'missing_install_id',
        'Send a random install id in the X-Install-Id header.',
      );
    }

    for (final (limiter, key) in [
      (installLimiter, 'install:$installId'),
      (ipLimiter, 'ip:${_clientIp(request)}'),
    ]) {
      final wait = limiter.tryAcquire(key);
      if (wait != null) {
        _log({'event': 'rate_limited', 'scope': key.split(':').first});
        return _error(
          429,
          'rate_limited',
          "You've run several checks in a short time. Please try again "
              'shortly.',
          headers: {'retry-after': '${wait.inSeconds + 1}'},
        );
      }
    }

    final length = request.contentLength;
    if (length != null && length > maxBodyBytes) {
      return _error(413, 'too_large', 'The photos are too large.');
    }

    final CheckRequest checkRequest;
    try {
      final body = await _readBody(request);
      checkRequest = CheckRequest.fromJson(jsonDecode(body));
    } on _BodyTooLarge {
      return _error(413, 'too_large', 'The photos are too large.');
    } on FormatException {
      return _error(400, 'invalid_json', 'The request body is not valid JSON.');
    } on InvalidCheckRequest catch (e) {
      return _error(400, 'invalid_request', e.message);
    }

    try {
      final analysis = await concurrency
          .run(() => _analyzer.analyze(checkRequest, userId: installId))
          .timeout(analysisTimeout);
      final result = analysis.result;
      // Operational metadata only: no answers, notes, photos, or findings.
      _log({
        'event': 'check',
        'id': result.id,
        'status': result.status.id,
        'urgency': result.urgency?.id,
        'escalated': result.escalatedBySafetyRules,
        'photos': checkRequest.photos.length,
        'ms': watch.elapsedMilliseconds,
        ...analysis.stats.toJson(),
      });
      return _json(200, result.toJson());
    } on Overloaded {
      _log({'event': 'overloaded', 'queued': concurrency.queued});
      return _busy();
    } on TimeoutException {
      _log({'event': 'timeout', 'ms': watch.elapsedMilliseconds});
      return _error(
        504,
        'timeout',
        'The analysis took too long. Please try again.',
      );
    } on AnalysisFailed catch (e) {
      final cause = e.cause;
      _log({
        'event': 'analysis_failed',
        'cause': cause is ClaudeApiException
            ? '${cause.statusCode} ${cause.type} ${cause.requestId ?? ''}'
            : '${cause.runtimeType}',
        'ms': watch.elapsedMilliseconds,
      });
      if (cause is ClaudeApiException && cause.isTransient) return _busy();
      return _error(
        502,
        'analysis_failed',
        "We couldn't finish this analysis. Please try again.",
      );
    }
  }

  Response _busy() => _error(
    503,
    'busy',
    'SpotCheck is very busy right now. Please try again in a minute.',
    headers: {'retry-after': '30'},
  );

  String _clientIp(Request request) {
    // Behind a load balancer the client is the first forwarded address.
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    final info = request.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
  }

  Future<String> _readBody(Request request) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request.read()) {
      bytes.add(chunk);
      if (bytes.length > maxBodyBytes) throw _BodyTooLarge();
    }
    return utf8.decode(bytes.takeBytes());
  }

  Middleware _cors() =>
      (inner) => (request) async {
        final origin = request.headers['origin'];
        final allowed =
            origin != null &&
            (corsOrigins.contains('*') || corsOrigins.contains(origin));
        final headers = {
          if (allowed) ...{
            'access-control-allow-origin': corsOrigins.contains('*')
                ? '*'
                : origin,
            'access-control-allow-methods': 'GET, POST, OPTIONS',
            'access-control-allow-headers': 'content-type, x-install-id',
            'access-control-max-age': '600',
            'vary': 'origin',
          },
        };
        if (request.method == 'OPTIONS') {
          return Response(allowed ? 204 : 403, headers: headers);
        }
        final response = await inner(request);
        return response.change(headers: headers);
      };

  static Handler _securityHeaders(Handler inner) => (request) async {
    final response = await inner(request);
    return response.change(
      headers: {
        'cache-control': 'no-store',
        'x-content-type-options': 'nosniff',
      },
    );
  };

  static Response _json(
    int status,
    Object body, {
    Map<String, String> headers = const {},
  }) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json; charset=utf-8', ...headers},
  );

  static Response _error(
    int status,
    String code,
    String message, {
    Map<String, String> headers = const {},
  }) => _json(status, {
    'error': {'code': code, 'message': message},
  }, headers: headers);

  static void _stdoutLog(Map<String, Object?> event) {
    stdout.writeln(
      jsonEncode({'ts': DateTime.now().toUtc().toIso8601String(), ...event}),
    );
  }
}

class _BodyTooLarge implements Exception {}
