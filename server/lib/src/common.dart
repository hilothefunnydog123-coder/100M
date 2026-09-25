import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

typedef Clock = DateTime Function();
typedef LogSink = void Function(Map<String, Object?> event);

DateTime systemClock() => DateTime.now().toUtc();

/// One JSON line per event on stdout, for log collectors.
void stdoutLog(Map<String, Object?> event) => stdout.writeln(
  jsonEncode({'ts': DateTime.now().toUtc().toIso8601String(), ...event}),
);

/// An error the client should see: an HTTP status, a stable machine code,
/// and a message written for the person using the app.
class ApiError implements Exception {
  ApiError(
    this.status,
    this.code,
    this.message, {
    this.retryAfter,
    this.details = const {},
  });

  ApiError.badRequest(String code, String message) : this(400, code, message);

  ApiError.notFound([String message = 'Not found.'])
    : this(404, 'not_found', message);

  ApiError.forbidden([String message = 'Only the account owner can do that.'])
    : this(403, 'forbidden', message);

  ApiError.unauthorized([String message = 'Sign in again to continue.'])
    : this(401, 'unauthorized', message);

  final int status;
  final String code;
  final String message;
  final Duration? retryAfter;

  /// Extra fields merged into the JSON body next to `error`.
  final Map<String, Object?> details;

  static ApiError rateLimited(Duration wait, [String? message]) => ApiError(
    429,
    'rate_limited',
    message ?? 'Too many requests. Please try again shortly.',
    retryAfter: wait,
  );

  static ApiError unavailable(String code, String message) =>
      ApiError(503, code, message);

  @override
  String toString() => 'ApiError($status $code: $message)';
}

final _secureRandom = Random.secure();

/// URL-safe random secret with [bytes] of entropy, e.g. session tokens.
String randomToken([int bytes = 32]) => base64Url
    .encode(List<int>.generate(bytes, (_) => _secureRandom.nextInt(256)))
    .replaceAll('=', '');

/// Random lowercase id without look-alike characters, for customer links.
String randomSlug(int length) {
  const alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';
  return List.generate(
    length,
    (_) => alphabet[_secureRandom.nextInt(alphabet.length)],
  ).join();
}

/// A zero-padded numeric code, e.g. `042913`.
String randomDigits(int length) =>
    List.generate(length, (_) => _secureRandom.nextInt(10)).join();

String sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

String hmacHex(String key, String value) =>
    Hmac(sha256, utf8.encode(key)).convert(utf8.encode(value)).toString();

final _emailPattern = RegExp(r'^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@.]{2,}$');

/// Lowercased and trimmed, or null when it isn't a plausible address.
String? normalizeEmail(Object? value) {
  if (value is! String) return null;
  final email = value.trim().toLowerCase();
  if (email.length > 200 || !_emailPattern.hasMatch(email)) return null;
  return email;
}

/// Hides most of an address for logs: `d***@example.com`.
String maskEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 0) return '***';
  return '${email[0]}***${email.substring(at)}';
}

Map<String, Object?> asMap(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

String? asString(Object? value) => value is String ? value : null;

int? asInt(Object? value) => switch (value) {
  final int v => v,
  final num v when v == v.roundToDouble() => v.toInt(),
  final String v => int.tryParse(v),
  _ => null,
};
