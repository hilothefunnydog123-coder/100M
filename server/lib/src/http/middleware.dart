import 'dart:async';

import 'package:shelf/shelf.dart';

import '../common.dart';
import '../metrics.dart';
import '../pages.dart';
import 'respond.dart';

final _requestIdPattern = RegExp(r'^[A-Za-z0-9._-]{8,64}$');

/// Tags each request with an id (the caller's X-Request-Id if sane), echoed
/// in the response and in logs, so a user's error can be traced.
Middleware requestIds() =>
    (inner) => (request) async {
      final given = request.headers['x-request-id'];
      final id = given != null && _requestIdPattern.hasMatch(given)
          ? given
          : randomSlug(20);
      final response = await inner(request.change(context: {requestIdKey: id}));
      return response.change(headers: {'x-request-id': id});
    };

/// One log line and the standard HTTP metrics per request. Routes are
/// normalized (ids removed) to keep metric cardinality bounded.
Middleware accessLog(LogSink log, Metrics metrics) {
  final requests = metrics.counter(
    'jobwalk_http_requests_total',
    'HTTP requests by route and status.',
    labels: ['method', 'route', 'status'],
  );
  final duration = metrics.histogram(
    'jobwalk_http_request_duration_seconds',
    'HTTP request latency.',
    labels: ['route'],
    buckets: const [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60, 120],
  );
  return (inner) => (request) async {
    final watch = Stopwatch()..start();
    final response = await inner(request);
    final route = routeLabel(request);
    final seconds = watch.elapsedMicroseconds / 1e6;
    requests.inc([request.method, route, '${response.statusCode}']);
    duration.observe(seconds, [route]);
    if (route != '/healthz' && route != '/metrics') {
      log({
        'event': 'request',
        'id': requestId(request),
        'method': request.method,
        'route': route,
        'status': response.statusCode,
        'ms': watch.elapsedMilliseconds,
      });
    }
    return response;
  };
}

const _staticRoutes = {
  '/', '/sample', '/waitlist', '/healthz', '/readyz', '/metrics', //
  '/robots.txt', '/billing/done', '/billing/cancelled', '/payments/done',
  '/payments/refresh', '/webhooks/stripe', '/v1/auth/code',
  '/v1/auth/verify', '/v1/auth/sign-out', '/v1/me', '/v1/business',
  '/v1/business/numbers', '/v1/team', '/v1/quotes', '/v1/activity',
  '/v1/drafts', '/v1/billing/checkout', '/v1/billing/portal',
  '/v1/payments', '/v1/payments/connect', '/v1/payments/dashboard',
  '/v1/account', '/v1/account/export', '/admin/stats',
  '/admin/waitlist.csv', '/admin/jobs',
};

final _patterns = [
  (RegExp(r'^/q/[^/]+$'), '/q/:id'),
  (RegExp(r'^/q/[^/]+/(approve|decline|deposit)$'), null),
  (RegExp(r'^/v1/quotes/[^/]+$'), '/v1/quotes/:id'),
  (RegExp(r'^/v1/quotes/[^/]+/publish$'), '/v1/quotes/:id/publish'),
  (RegExp(r'^/v1/photos/[^/]+$'), '/v1/photos/:id'),
  (RegExp(r'^/v1/team/[^/]+$'), '/v1/team/:id'),
  (RegExp(r'^/admin/jobs/[^/]+/retry$'), '/admin/jobs/:id/retry'),
];

String routeLabel(Request r) {
  final path = '/${r.url.path}';
  if (_staticRoutes.contains(path)) return path;
  for (final (pattern, label) in _patterns) {
    final m = pattern.firstMatch(path);
    if (m == null) continue;
    return label ?? '/q/:id/${m.group(1)}';
  }
  return 'unmatched';
}

bool isApiPath(Request r) {
  final p = r.url.path;
  return p.startsWith('v1/') ||
      p.startsWith('admin/') ||
      p.startsWith('webhooks/') ||
      p == 'healthz' ||
      p == 'readyz';
}

/// Turns [ApiError]s into responses (JSON for the API, a page for people)
/// and anything unexpected into a logged 500 that leaks nothing.
Middleware errors(LogSink log) =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on ApiError catch (e) {
        return _render(request, e);
      } on Object catch (e, stack) {
        log({
          'event': 'error',
          'id': requestId(request),
          'route': routeLabel(request),
          'error': '$e',
          'stack': stack.toString().split('\n').take(12).join('\n'),
        });
        return _render(
          request,
          ApiError(
            500,
            'internal',
            'Something went wrong on our side. Please try again.',
          ),
        );
      }
    };

Response _render(Request request, ApiError e) {
  if (isApiPath(request)) {
    return errorJson(e, requestId: requestId(request));
  }
  final title = switch (e.status) {
    404 => 'Page not found',
    429 => 'Slow down a moment',
    _ => 'Something went wrong',
  };
  return htmlResponse(
    e.status,
    messagePage(
      title,
      e.status == 404
          ? 'This link may be mistyped or the quote was removed. Ask the '
                'contractor who sent it for a new link.'
          : e.message,
      homeHref: '/',
    ),
    headers: {
      if (e.retryAfter != null)
        'retry-after': '${(e.retryAfter!.inMilliseconds / 1000).ceil()}',
    },
  );
}

/// CORS for the API, for the web build of the app.
Middleware cors(List<String> origins) =>
    (inner) => (request) async {
      final origin = request.headers['origin'];
      final any = origins.contains('*');
      final allowed = origin != null && (any || origins.contains(origin));
      final api = request.url.path.startsWith('v1/');
      final headers = {
        if (allowed && api) ...{
          'access-control-allow-origin': any ? '*' : origin,
          'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'access-control-allow-headers':
              'authorization, content-type, idempotency-key, x-request-id',
          'access-control-expose-headers': 'x-request-id, retry-after',
          'access-control-max-age': '600',
          'vary': 'origin',
        },
      };
      if (request.method == 'OPTIONS') {
        return Response(headers.isEmpty ? 403 : 204, headers: headers);
      }
      final response = await inner(request);
      return response.change(headers: headers);
    };

Middleware securityHeaders({required bool hsts}) =>
    (inner) => (request) async {
      final response = await inner(request);
      final html = (response.mimeType ?? '') == 'text/html';
      return response.change(
        headers: {
          if (!response.headers.containsKey('cache-control'))
            'cache-control': 'no-store',
          'x-content-type-options': 'nosniff',
          'referrer-policy': 'no-referrer',
          if (hsts) 'strict-transport-security': 'max-age=31536000',
          if (html) ...{
            'content-security-policy':
                "default-src 'none'; style-src 'unsafe-inline'; img-src "
                "'self' data:; form-action 'self' https://checkout.stripe.com; "
                "base-uri 'none'; frame-ancestors 'none'",
            'x-frame-options': 'DENY',
          },
        },
      );
    };

/// Answers with 503 while the server drains for shutdown, so the load
/// balancer moves traffic elsewhere.
Middleware drain(bool Function() draining) =>
    (inner) => (request) {
      if (draining() && request.url.path != 'healthz') {
        return Future.value(
          errorJson(
            ApiError.unavailable('shutting_down', 'Restarting. Try again.'),
          ).change(headers: {'connection': 'close', 'retry-after': '2'}),
        );
      }
      return inner(request);
    };
