import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import '../common.dart';

const requestIdKey = 'jobwalk.request_id';

String requestId(Request r) => (r.context[requestIdKey] as String?) ?? '';

Response jsonResponse(
  int status,
  Object? body, {
  Map<String, String> headers = const {},
}) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8', ...headers},
);

Response htmlResponse(
  int status,
  String body, {
  Map<String, String> headers = const {},
}) => Response(
  status,
  body: body,
  headers: {'content-type': 'text/html; charset=utf-8', ...headers},
);

Response seeOther(String location) =>
    Response(303, headers: {'location': location});

Response errorJson(ApiError e, {String requestId = ''}) => jsonResponse(
  e.status,
  {
    'error': {
      'code': e.code,
      'message': e.message,
      if (requestId.isNotEmpty) 'request_id': requestId,
    },
    ...e.details,
  },
  headers: {
    if (e.retryAfter != null)
      'retry-after': '${(e.retryAfter!.inMilliseconds / 1000).ceil()}',
  },
);

/// Reads the body, refusing more than [maxBytes] even when the client
/// lies about Content-Length.
Future<Uint8List> readBytes(Request r, int maxBytes) async {
  final declared = r.contentLength;
  if (declared != null && declared > maxBytes) throw _tooLarge(maxBytes);
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in r.read()) {
    bytes.add(chunk);
    if (bytes.length > maxBytes) throw _tooLarge(maxBytes);
  }
  return bytes.takeBytes();
}

ApiError _tooLarge(int maxBytes) => ApiError(
  413,
  'too_large',
  'The request is too large (limit ${maxBytes ~/ 1024} KB).',
);

/// A JSON object body. An empty body reads as `{}`.
Future<Map<String, Object?>> readJson(
  Request r, {
  int maxBytes = 64 * 1024,
}) async {
  final bytes = await readBytes(r, maxBytes);
  if (bytes.isEmpty) return {};
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw ApiError.badRequest('invalid_json', 'The body is not valid JSON.');
  }
  if (json is! Map<String, Object?>) {
    throw ApiError.badRequest('invalid_json', 'Send a JSON object.');
  }
  return json;
}

Future<Map<String, String>> readForm(
  Request r, {
  int maxBytes = 16 * 1024,
}) async {
  final body = utf8.decode(await readBytes(r, maxBytes), allowMalformed: true);
  try {
    return Uri.splitQueryString(body);
  } on Object {
    return const {};
  }
}

String? bearerToken(Request r) {
  final header = r.headers['authorization'] ?? '';
  const prefix = 'Bearer ';
  if (!header.startsWith(prefix)) return null;
  final token = header.substring(prefix.length).trim();
  return token.isEmpty || token.length > 200 ? null : token;
}

/// The caller's address. Behind [trustedProxies] load balancers, each of
/// which appends to X-Forwarded-For, the client is that many entries from
/// the end; anything before it is client-supplied and ignored.
String clientIp(Request r, {int trustedProxies = 1}) {
  if (trustedProxies > 0) {
    final forwarded = r.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) {
      final hops = [
        for (final h in forwarded.split(','))
          if (h.trim().isNotEmpty) h.trim(),
      ];
      if (hops.isNotEmpty) {
        final i = hops.length - trustedProxies;
        return hops[i < 0 ? 0 : i];
      }
    }
  }
  final info = r.context['shelf.io.connection_info'];
  return info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
}

int? queryInt(Request r, String name) =>
    int.tryParse(r.url.queryParameters[name] ?? '');
