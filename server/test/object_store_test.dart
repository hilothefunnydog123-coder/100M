import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jobwalk_server/src/integrations/object_store.dart';
import 'package:test/test.dart';

void main() {
  // The worked examples from the Amazon S3 documentation, "Signature
  // Calculations for the Authorization Header" and "Authenticating
  // Requests: Using Query Parameters".
  final signer = SigV4(
    accessKey: 'AKIAIOSFODNN7EXAMPLE',
    secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    region: 'us-east-1',
  );
  final docsTime = DateTime.utc(2013, 5, 24);
  final emptyHash = sha256.convert(const []).toString();

  test('header signature matches the AWS example', () {
    final headers = signer.signHeaders(
      method: 'GET',
      url: Uri.parse('https://examplebucket.s3.amazonaws.com/test.txt'),
      headers: {'Range': 'bytes=0-9'},
      payloadHash: emptyHash,
      now: docsTime,
    );
    expect(
      headers['authorization'],
      'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/'
      's3/aws4_request, SignedHeaders=host;range;x-amz-content-sha256;'
      'x-amz-date, Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48'
      'dd91039c6036bdb41',
    );
    expect(headers['x-amz-date'], '20130524T000000Z');
  });

  test('presigned URL matches the AWS example', () {
    final url = signer.presign(
      method: 'GET',
      url: Uri.parse('https://examplebucket.s3.amazonaws.com/test.txt'),
      now: docsTime,
      expires: const Duration(days: 1),
    );
    expect(
      url.queryParameters['X-Amz-Signature'],
      'aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404',
    );
    expect(url.queryParameters['X-Amz-Expires'], '86400');
  });

  test('signs Supabase Storage requests the way botocore does', () async {
    // Supabase's S3 endpoint has a path, which belongs in the signature.
    // Expected values come from botocore 1.43 (S3SigV4Auth and
    // S3SigV4QueryAuth) signing the same requests.
    final sent = <http.Request>[];
    final store = S3ObjectStore(
      endpoint: Uri.parse(
        'https://abcdefghijklmnop.storage.supabase.co/storage/v1/s3',
      ),
      bucket: 'photos',
      region: 'us-east-1',
      accessKey: 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6',
      secretKey:
          'f00dfeedf00dfeedf00dfeedf00dfeedf00dfeedf00dfeedf00dfeedf00dfeed',
      client: MockClient((r) async {
        sent.add(r);
        return http.Response('', 200);
      }),
      clock: () => DateTime.utc(2026, 9, 27, 12),
    );
    await store.put(
      'b/b_1/p_1.jpg',
      Uint8List.fromList([1, 2, 3]),
      contentType: 'image/jpeg',
    );
    expect(
      sent.single.url.toString(),
      'https://abcdefghijklmnop.storage.supabase.co/storage/v1/s3/photos/b/'
      'b_1/p_1.jpg',
    );
    expect(
      sent.single.headers['authorization'],
      'AWS4-HMAC-SHA256 Credential=a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6/20260927/'
      'us-east-1/s3/aws4_request, SignedHeaders=content-type;host;'
      'x-amz-content-sha256;x-amz-date, Signature=c976369085fbe60114b51298b4'
      'caad63630459418c3f63f73d98fcc7b1a95d47',
    );
    final url = store.signedUrl(
      'b/b_1/p_1.jpg',
      expires: const Duration(minutes: 10),
    )!;
    expect(url.path, '/storage/v1/s3/photos/b/b_1/p_1.jpg');
    expect(
      url.queryParameters['X-Amz-Signature'],
      '2167a323ac4df22a936f0d6cc9502999111493e57f984adfa743c4f43606b40d',
    );
  });

  group('S3 store', () {
    late List<http.Request> requests;
    late S3ObjectStore store;
    final objects = <String, List<int>>{};

    setUp(() {
      requests = [];
      objects.clear();
      store = S3ObjectStore(
        endpoint: Uri.parse('https://account.r2.cloudflarestorage.com'),
        bucket: 'jobwalk',
        region: 'auto',
        accessKey: 'key',
        secretKey: 'secret',
        clock: () => docsTime,
        client: MockClient((r) async {
          requests.add(r);
          final key = r.url.path;
          switch (r.method) {
            case 'PUT':
              objects[key] = r.bodyBytes;
              return http.Response('', 200);
            case 'GET':
              final o = objects[key];
              return o == null
                  ? http.Response('<Error/>', 404)
                  : http.Response.bytes(o, 200);
            case 'DELETE':
              objects.remove(key);
              return http.Response('', 204);
          }
          return http.Response('', 405);
        }),
      );
    });

    test('put, get, delete with signed requests', () async {
      final bytes = Uint8List.fromList(utf8.encode('photo'));
      await store.put('b/b_1/p_1.jpg', bytes, contentType: 'image/jpeg');
      final put = requests.single;
      expect(put.url.path, '/jobwalk/b/b_1/p_1.jpg');
      expect(put.headers['authorization'], startsWith('AWS4-HMAC-SHA256'));
      expect(
        put.headers['x-amz-content-sha256'],
        sha256.convert(bytes).toString(),
      );
      expect(put.headers['content-type'], 'image/jpeg');

      expect(await store.get('b/b_1/p_1.jpg'), bytes);
      await store.delete('b/b_1/p_1.jpg');
      expect(await store.get('b/b_1/p_1.jpg'), isNull);
    });

    test('signed URLs point at the object', () {
      final url = store.signedUrl('b/b_1/p_1.jpg')!;
      expect(url.host, 'account.r2.cloudflarestorage.com');
      expect(url.path, '/jobwalk/b/b_1/p_1.jpg');
      expect(url.queryParameters['X-Amz-Expires'], '300');
    });

    test('errors surface as ObjectStoreException', () async {
      final failing = S3ObjectStore(
        endpoint: Uri.parse('https://s3.example.com'),
        bucket: 'b',
        region: 'us-east-1',
        accessKey: 'k',
        secretKey: 's',
        client: MockClient((_) async => http.Response('nope', 500)),
      );
      expect(
        () => failing.put('a.jpg', Uint8List(1), contentType: 'image/jpeg'),
        throwsA(isA<ObjectStoreException>()),
      );
    });
  });

  test('file store keeps objects on disk and refuses unsafe keys', () async {
    final dir = await Directory.systemTemp.createTemp('objects');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileObjectStore(dir);
    await store.put(
      'b/b_1/p_1.jpg',
      Uint8List.fromList([1, 2, 3]),
      contentType: 'image/jpeg',
    );
    expect(await store.get('b/b_1/p_1.jpg'), [1, 2, 3]);
    expect(store.signedUrl('b/b_1/p_1.jpg'), isNull);
    await store.delete('b/b_1/p_1.jpg');
    expect(await store.get('b/b_1/p_1.jpg'), isNull);
    for (final bad in ['../x', '/etc/passwd', 'a/../../b', 'a//b', '']) {
      expect(
        () => store.put(bad, Uint8List(1), contentType: 'x'),
        throwsArgumentError,
        reason: bad,
      );
    }
  });
}
