import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class StripeException implements Exception {
  StripeException(this.statusCode, this.message, {this.type = '', this.code});

  final int statusCode;
  final String message;
  final String type;
  final String? code;

  bool get retryable => statusCode == 429 || statusCode >= 500;

  @override
  String toString() => 'StripeException($statusCode $type: $message)';
}

/// The few Stripe REST calls Jobwalk makes, with form encoding done right.
///
/// No official Dart SDK exists; this follows the documented REST contract.
class StripeClient {
  StripeClient({
    required this.secretKey,
    http.Client? client,
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 30),
  }) : _http = client ?? http.Client(),
       _base = baseUrl ?? Uri.parse('https://api.stripe.com');

  static const apiVersion = '2024-06-20';

  final String secretKey;
  final Duration timeout;
  final http.Client _http;
  final Uri _base;

  Map<String, String> _headers({String? account, String? idempotencyKey}) => {
    'authorization': 'Bearer $secretKey',
    'stripe-version': apiVersion,
    'Stripe-Account': ?account,
    'Idempotency-Key': ?idempotencyKey,
  };

  Future<Map<String, Object?>> post(
    String path,
    Map<String, Object?> params, {
    String? idempotencyKey,
    String? account,
  }) => _send(
    () => _http.post(
      _base.replace(path: path),
      headers: {
        ..._headers(account: account, idempotencyKey: idempotencyKey),
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: encodeStripeForm(params),
    ),
  );

  Future<Map<String, Object?>> get(String path, {String? account}) => _send(
    () => _http.get(
      _base.replace(path: path),
      headers: _headers(account: account),
    ),
  );

  Future<Map<String, Object?>> delete(String path, {String? account}) => _send(
    () => _http.delete(
      _base.replace(path: path),
      headers: _headers(account: account),
    ),
  );

  Future<Map<String, Object?>> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw StripeException(504, 'Stripe did not respond in time.');
    } on http.ClientException catch (e) {
      throw StripeException(503, 'Could not reach Stripe: ${e.message}');
    }
    Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      body = null;
    }
    if (response.statusCode == 200 && body is Map<String, Object?>) {
      return body;
    }
    final error = body is Map ? body['error'] : null;
    throw StripeException(
      response.statusCode,
      error is Map
          ? '${error['message'] ?? 'Stripe error'}'
          : 'Stripe HTTP ${response.statusCode}',
      type: error is Map ? '${error['type'] ?? ''}' : '',
      code: error is Map ? error['code'] as String? : null,
    );
  }
}

/// Stripe's form encoding: nested maps and lists become `a[b][0]=c`.
String encodeStripeForm(Map<String, Object?> params) {
  final pairs = <String>[];
  void add(String key, Object? value) {
    switch (value) {
      case null:
        return;
      case Map<String, Object?>():
        for (final e in value.entries) {
          add('$key[${e.key}]', e.value);
        }
      case List<Object?>():
        for (final (i, v) in value.indexed) {
          add('$key[$i]', v);
        }
      default:
        pairs.add(
          '${Uri.encodeQueryComponent(key)}='
          '${Uri.encodeQueryComponent('$value')}',
        );
    }
  }

  for (final e in params.entries) {
    add(e.key, e.value);
  }
  return pairs.join('&');
}

class WebhookSignatureException implements Exception {
  WebhookSignatureException(this.message);

  final String message;

  @override
  String toString() => 'WebhookSignatureException: $message';
}

/// Checks a `Stripe-Signature` header and returns the decoded event.
///
/// The signature is HMAC-SHA256 of `"<timestamp>.<payload>"` with the
/// endpoint's signing secret. Old timestamps are rejected to stop replays.
Map<String, Object?> verifyStripeWebhook(
  String payload,
  String? header,
  String secret, {
  required DateTime now,
  Duration tolerance = const Duration(minutes: 5),
}) {
  if (header == null || header.isEmpty) {
    throw WebhookSignatureException('Missing Stripe-Signature header.');
  }
  int? timestamp;
  final signatures = <String>[];
  for (final part in header.split(',')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    final k = part.substring(0, i).trim();
    final v = part.substring(i + 1).trim();
    if (k == 't') timestamp = int.tryParse(v);
    if (k == 'v1') signatures.add(v);
  }
  if (timestamp == null || signatures.isEmpty) {
    throw WebhookSignatureException('Malformed Stripe-Signature header.');
  }
  final age = now.difference(
    DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true),
  );
  if (age.abs() > tolerance) {
    throw WebhookSignatureException('Timestamp outside the tolerance.');
  }
  final expected = Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode('$timestamp.$payload')).toString();
  if (!signatures.any((s) => constantTimeEquals(s, expected))) {
    throw WebhookSignatureException('No matching signature.');
  }
  final event = jsonDecode(payload);
  if (event is! Map<String, Object?>) {
    throw WebhookSignatureException('Payload is not an event object.');
  }
  return event;
}

/// Builds a valid `Stripe-Signature` header, for tests and local tools.
String signStripePayload(String payload, String secret, DateTime at) {
  final t = at.millisecondsSinceEpoch ~/ 1000;
  final sig = Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode('$t.$payload')).toString();
  return 't=$t,v1=$sig';
}

bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
