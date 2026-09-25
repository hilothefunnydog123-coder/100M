import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jobwalk/services/api.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

final now = DateTime.utc(2026, 9, 25, 15);

PublicQuote publicQuote() => PublicQuote.fromQuote(
  QuoteBuilder.fromDraft(
    SampleJob.driveway.draft,
    id: 'q',
    number: 1001,
    rates: Rates.forTrade(Trade.pressureWashing),
    now: now,
  ),
  const BusinessProfile(name: 'Shine Pressure Washing'),
  issuedAt: now,
);

http.Response json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  final requests = <http.Request>[];
  HttpJobwalkClient client(http.Response Function(http.Request) reply) =>
      HttpJobwalkClient(
        baseUrl: Uri.parse('https://api.example.com/jobwalk/'),
        installId: 'inst_test123',
        client: MockClient((r) async {
          requests.add(r);
          return reply(r);
        }),
      );

  setUp(requests.clear);

  test('drafts keep the base path and send the install id', () async {
    final c = client(
      (_) => json(200, {
        'draft': SampleJob.fence.draft.toJson(),
        'model': 'claude-opus-5-5',
        'demo': false,
      }),
    );
    final r = await c.draft(
      DraftRequest(
        profile: const BusinessProfile(name: 'Oak & Iron'),
        rates: const Rates(),
        photos: const [],
      ),
    );
    expect(r.model, 'claude-opus-5-5');
    expect(r.draft.tiers, hasLength(3));
    final req = requests.single;
    expect(req.url.toString(), 'https://api.example.com/jobwalk/v1/drafts');
    expect(req.headers['x-install-id'], 'inst_test123');
    expect(
      jsonDecode(req.body),
      containsPair('rates', isA<Map<String, Object?>>()),
    );
  });

  test('publish, update, and status use the owner token', () async {
    final c = client((r) {
      if (r.method == 'POST') {
        return json(201, {
          'id': 'abc123',
          'url': 'https://jobwalk.app/q/abc123',
          'owner_token': 'secret',
          'revision': 1,
        });
      }
      if (r.method == 'PUT') return json(200, {'revision': 2});
      return json(200, {'response': const CustomerResponse(views: 3).toJson()});
    });
    final share = await c.publish(publicQuote());
    expect(share.url, 'https://jobwalk.app/q/abc123');
    expect(await c.update(share.id, share.ownerToken, publicQuote()), 2);
    final status = await c.status(share.id, share.ownerToken);
    expect(status.views, 3);

    expect(requests[0].url.path, '/jobwalk/v1/quotes');
    expect(requests[0].headers['authorization'], isNull);
    expect(requests[1].url.path, '/jobwalk/v1/quotes/abc123');
    expect(requests[1].headers['authorization'], 'Bearer secret');
    expect(requests[2].method, 'GET');
    expect(requests[2].headers['authorization'], 'Bearer secret');
  });

  test('server errors keep their message and retry hint', () async {
    Future<ApiError> errorFor(int status, {String? message}) async {
      final c = client(
        (_) => json(status, {
          if (message != null) 'error': {'code': 'x', 'message': message},
        }),
      );
      try {
        await c.status('id', 'token');
      } on ApiError catch (e) {
        return e;
      }
      fail('expected an ApiError');
    }

    final bad = await errorFor(400, message: 'At least one photo is required.');
    expect(bad.message, 'At least one photo is required.');
    expect(bad.retryable, isFalse);
    expect((await errorFor(409)).retryable, isFalse);
    expect((await errorFor(404)).retryable, isFalse);
    expect((await errorFor(429)).retryable, isTrue);
    final busy = await errorFor(503, message: 'Jobwalk is very busy.');
    expect(busy.message, 'Jobwalk is very busy.');
    expect(busy.retryable, isTrue);
  });

  test('network failures and junk bodies become friendly errors', () async {
    final offline = HttpJobwalkClient(
      baseUrl: Uri.parse('https://api.example.com'),
      installId: 'inst_test123',
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      offline.status('id', 'token'),
      throwsA(
        isA<ApiError>().having((e) => e.message, 'message', contains('reach')),
      ),
    );
    final junk = client((_) => http.Response('<html>oops</html>', 200));
    await expectLater(junk.status('id', 'token'), throwsA(isA<ApiError>()));
  });
}
