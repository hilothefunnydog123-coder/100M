import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Where job photos live. Keys look like `b/<business>/<photo>.jpg`.
abstract interface class ObjectStore {
  Future<void> put(String key, Uint8List bytes, {required String contentType});

  /// The object's bytes, or null if there is no such key.
  Future<Uint8List?> get(String key);

  Future<void> delete(String key);

  /// A short-lived URL that downloads [key] directly, or null when this
  /// store can't make one (then the API streams the bytes itself).
  Uri? signedUrl(String key, {Duration expires = const Duration(minutes: 5)});
}

class ObjectStoreException implements Exception {
  ObjectStoreException(this.message);

  final String message;

  @override
  String toString() => 'ObjectStoreException: $message';
}

final _safeKey = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$',
);

void _checkKey(String key) {
  if (!_safeKey.hasMatch(key) || key.contains('..')) {
    throw ArgumentError.value(key, 'key', 'Unsafe object key.');
  }
}

class MemoryObjectStore implements ObjectStore {
  final objects = <String, (Uint8List, String)>{};

  @override
  Future<void> put(
    String key,
    Uint8List bytes, {
    required String contentType,
  }) async {
    _checkKey(key);
    objects[key] = (bytes, contentType);
  }

  @override
  Future<Uint8List?> get(String key) async => objects[key]?.$1;

  @override
  Future<void> delete(String key) async => objects.remove(key);

  @override
  Uri? signedUrl(String key, {Duration expires = const Duration(minutes: 5)}) =>
      null;
}

/// Files on a local or mounted disk. For development and single-server
/// deployments with a persistent volume.
class FileObjectStore implements ObjectStore {
  FileObjectStore(this.dir);

  final Directory dir;

  File _file(String key) {
    _checkKey(key);
    return File('${dir.path}/$key');
  }

  @override
  Future<void> put(
    String key,
    Uint8List bytes, {
    required String contentType,
  }) async {
    final file = _file(key);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<Uint8List?> get(String key) async {
    final file = _file(key);
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Uri? signedUrl(String key, {Duration expires = const Duration(minutes: 5)}) =>
      null;
}

/// Any S3-compatible bucket: AWS S3, Cloudflare R2, Backblaze B2, MinIO.
/// Uses path-style URLs (`endpoint/bucket/key`), which all of them accept.
class S3ObjectStore implements ObjectStore {
  S3ObjectStore({
    required this.endpoint,
    required this.bucket,
    required String region,
    required String accessKey,
    required String secretKey,
    http.Client? client,
    DateTime Function()? clock,
  }) : _signer = SigV4(
         accessKey: accessKey,
         secretKey: secretKey,
         region: region,
       ),
       _http = client ?? http.Client(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final Uri endpoint;
  final String bucket;
  final SigV4 _signer;
  final http.Client _http;
  final DateTime Function() _clock;

  Uri _url(String key) {
    _checkKey(key);
    final base = endpoint.path.replaceAll(RegExp(r'/+$'), '');
    return endpoint.replace(path: '$base/$bucket/$key');
  }

  Future<http.Response> _send(
    String method,
    String key, {
    Uint8List? body,
    String? contentType,
  }) async {
    final url = _url(key);
    final payload = body ?? Uint8List(0);
    final headers = _signer.signHeaders(
      method: method,
      url: url,
      headers: {'content-type': ?contentType},
      payloadHash: sha256.convert(payload).toString(),
      now: _clock(),
    );
    final request = http.Request(method, url)
      ..headers.addAll(headers)
      ..bodyBytes = payload;
    try {
      return await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(seconds: 30)),
      );
    } on Object catch (e) {
      throw ObjectStoreException('$method $key failed: $e');
    }
  }

  @override
  Future<void> put(
    String key,
    Uint8List bytes, {
    required String contentType,
  }) async {
    final r = await _send('PUT', key, body: bytes, contentType: contentType);
    if (r.statusCode != 200) {
      throw ObjectStoreException('PUT $key: HTTP ${r.statusCode}');
    }
  }

  @override
  Future<Uint8List?> get(String key) async {
    final r = await _send('GET', key);
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) {
      throw ObjectStoreException('GET $key: HTTP ${r.statusCode}');
    }
    return r.bodyBytes;
  }

  @override
  Future<void> delete(String key) async {
    final r = await _send('DELETE', key);
    if (r.statusCode != 204 && r.statusCode != 200 && r.statusCode != 404) {
      throw ObjectStoreException('DELETE $key: HTTP ${r.statusCode}');
    }
  }

  @override
  Uri? signedUrl(String key, {Duration expires = const Duration(minutes: 5)}) =>
      _signer.presign(
        method: 'GET',
        url: _url(key),
        now: _clock(),
        expires: expires,
      );
}

/// AWS Signature Version 4, as S3 uses it.
class SigV4 {
  SigV4({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    this.service = 's3',
  });

  final String accessKey;
  final String secretKey;
  final String region;
  final String service;

  static const unsignedPayload = 'UNSIGNED-PAYLOAD';

  /// Returns [headers] plus host, x-amz-date, x-amz-content-sha256, and
  /// authorization.
  Map<String, String> signHeaders({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    required String payloadHash,
    required DateTime now,
  }) {
    final date = _amzDate(now);
    final all = {
      for (final e in headers.entries) e.key.toLowerCase(): e.value.trim(),
      'host': _host(url),
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': date,
    };
    final names = all.keys.toList()..sort();
    final signedHeaders = names.join(';');
    final canonical = [
      method,
      _canonicalPath(url),
      _canonicalQuery(url.queryParametersAll),
      '${[for (final n in names) '$n:${all[n]}'].join('\n')}\n',
      signedHeaders,
      payloadHash,
    ].join('\n');
    final scope = _scope(now);
    final signature = _sign(now, _stringToSign(date, scope, canonical));
    return {
      ...all,
      'authorization':
          'AWS4-HMAC-SHA256 Credential=$accessKey/$scope, '
          'SignedHeaders=$signedHeaders, Signature=$signature',
    }..remove('host');
  }

  /// A presigned URL: the signature travels in the query string.
  Uri presign({
    required String method,
    required Uri url,
    required DateTime now,
    required Duration expires,
  }) {
    final date = _amzDate(now);
    final scope = _scope(now);
    final query = {
      ...url.queryParametersAll,
      'X-Amz-Algorithm': ['AWS4-HMAC-SHA256'],
      'X-Amz-Credential': ['$accessKey/$scope'],
      'X-Amz-Date': [date],
      'X-Amz-Expires': ['${expires.inSeconds}'],
      'X-Amz-SignedHeaders': ['host'],
    };
    final canonical = [
      method,
      _canonicalPath(url),
      _canonicalQuery(query),
      'host:${_host(url)}\n',
      'host',
      unsignedPayload,
    ].join('\n');
    final signature = _sign(now, _stringToSign(date, scope, canonical));
    final queryString = '${_canonicalQuery(query)}&X-Amz-Signature=$signature';
    return Uri.parse(
      '${url.scheme}://${url.authority}${_canonicalPath(url)}?$queryString',
    );
  }

  String _stringToSign(String date, String scope, String canonical) => [
    'AWS4-HMAC-SHA256',
    date,
    scope,
    sha256.convert(utf8.encode(canonical)).toString(),
  ].join('\n');

  String _sign(DateTime now, String stringToSign) {
    List<int> hmac(List<int> key, String data) =>
        Hmac(sha256, key).convert(utf8.encode(data)).bytes;
    final kDate = hmac(utf8.encode('AWS4$secretKey'), _day(now));
    final kRegion = hmac(kDate, region);
    final kService = hmac(kRegion, service);
    final kSigning = hmac(kService, 'aws4_request');
    return Hmac(sha256, kSigning).convert(utf8.encode(stringToSign)).toString();
  }

  String _scope(DateTime now) => '${_day(now)}/$region/$service/aws4_request';

  static String _host(Uri url) =>
      url.hasPort &&
          !((url.scheme == 'https' && url.port == 443) ||
              (url.scheme == 'http' && url.port == 80))
      ? '${url.host}:${url.port}'
      : url.host;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _day(DateTime t) {
    final u = t.toUtc();
    return '${u.year}${_two(u.month)}${_two(u.day)}';
  }

  static String _amzDate(DateTime t) {
    final u = t.toUtc();
    return '${_day(u)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
  }

  static String _canonicalPath(Uri url) {
    final path = url.path.isEmpty ? '/' : url.path;
    return path
        .split('/')
        .map((s) => _encode(Uri.decodeComponent(s)))
        .join('/');
  }

  static String _canonicalQuery(Map<String, List<String>> query) {
    final pairs =
        <(String, String)>[
          for (final e in query.entries)
            for (final v in e.value) (_encode(e.key), _encode(v)),
        ]..sort(
          (a, b) => a.$1 == b.$1 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1),
        );
    return pairs.map((p) => '${p.$1}=${p.$2}').join('&');
  }

  /// RFC 3986 encoding: everything but unreserved characters.
  static String _encode(String s) {
    final b = StringBuffer();
    for (final byte in utf8.encode(s)) {
      final c = String.fromCharCode(byte);
      if (RegExp(r'[A-Za-z0-9\-_.~]').hasMatch(c)) {
        b.write(c);
      } else {
        b.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return b.toString();
  }
}
