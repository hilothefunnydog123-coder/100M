import 'dart:typed_data';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jobwalk/services/api.dart';
import 'package:jobwalk/services/server.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

final now = DateTime.utc(2026, 9, 25, 15);

Quote quote() => QuoteBuilder.fromDraft(
  SampleJob.driveway.draft,
  id: 'q_test0001',
  number: 1001,
  rates: Rates.forTrade(Trade.pressureWashing),
  now: now,
);

http.Response json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  final requests = <http.Request>[];
  var unauthorized = 0;
  String? token = 'jws_token';

  ServerClient client(http.Response Function(http.Request) reply) =>
      ServerClient(
        baseUrl: Uri.parse('https://api.example.com/jobwalk/'),
        token: () => token,
        onUnauthorized: () => unauthorized++,
        client: MockClient((r) async {
          requests.add(r);
          return reply(r);
        }),
      );

  setUp(() {
    requests.clear();
    unauthorized = 0;
    token = 'jws_token';
  });

  test('drafts keep the base path and send the session and key', () async {
    final c = client(
      (_) => json(200, {
        'draft': SampleJob.driveway.draft.toJson(),
        'model': 'claude-opus-5-5',
      }),
    );
    final result = await c.draft(
      DraftRequest(
        profile: const BusinessProfile(name: 'Shine'),
        rates: const Rates(),
        photos: [
          JobPhoto(
            bytes: Uint8List.fromList([1, 2, 3]),
            mediaType: 'image/jpeg',
          ),
        ],
      ),
      idempotencyKey: 'draft_key_1',
    );
    final r = requests.single;
    expect(r.url.toString(), 'https://api.example.com/jobwalk/v1/drafts');
    expect(r.headers['authorization'], 'Bearer jws_token');
    expect(r.headers['idempotency-key'], 'draft_key_1');
    expect(result.model, 'claude-opus-5-5');
    expect(result.draft.items, isNotEmpty);
  });

  test('sign-in sends no token and returns the session', () async {
    token = null;
    final c = client(
      (r) => r.url.path.endsWith('/verify')
          ? json(200, {
              'token': 'jws_new',
              'created': true,
              'user': {
                'id': 'u_1',
                'email': 'dana@example.com',
                'role': 'owner',
              },
              'business': {
                'id': 'b_1',
                'profile': {'name': 'Brightline'},
                'setup_complete': true,
                'plan': {'id': 'trial', 'trial_drafts_left': 24},
              },
            })
          : json(200, {'ok': true}),
    );
    await c.requestCode('dana@example.com');
    final (session, account) = await c.verifyCode(
      'dana@example.com',
      '123456',
      device: 'iPhone',
    );
    expect(requests.first.headers.containsKey('authorization'), isFalse);
    expect(jsonDecode(requests.last.body), {
      'email': 'dana@example.com',
      'code': '123456',
      'device': 'iPhone',
    });
    expect(session, 'jws_new');
    expect(account.business.profile.name, 'Brightline');
    expect(account.business.plan.trialDraftsLeft, 24);
    expect(account.user.isOwner, isTrue);
  });

  test(
    'a stale version comes back as a conflict with the server copy',
    () async {
      final q = quote();
      final c = client(
        (_) => json(409, {
          'error': {'code': 'conflict', 'message': 'Changed elsewhere.'},
          'current': {'id': q.id, 'version': 4, 'quote': q.toJson()},
        }),
      );
      await expectLater(
        c.putQuote(q, baseVersion: 2),
        throwsA(
          isA<QuoteConflict>().having((e) => e.current.version, 'version', 4),
        ),
      );
      final sent = jsonDecode(requests.single.body) as Map<String, Object?>;
      expect(sent['base_version'], 2);
    },
  );

  test('401 ends the session', () async {
    final c = client(
      (_) => json(401, {
        'error': {'code': 'unauthorized', 'message': 'Sign in again.'},
      }),
    );
    await expectLater(c.me(), throwsA(isA<ApiError>()));
    expect(unauthorized, 1);
  });

  test('server errors keep their code, message, and retry hint', () async {
    Future<ApiError> fail(int status, String code) async {
      final c = client(
        (_) => json(status, {
          'error': {'code': code, 'message': 'From the server.'},
        }),
      );
      try {
        await c.me();
      } on ApiError catch (e) {
        return e;
      }
      throw StateError('no error');
    }

    final upgrade = await fail(402, 'upgrade_required');
    expect(upgrade.code, 'upgrade_required');
    expect(upgrade.status, 402);
    expect(upgrade.retryable, isFalse);
    expect(upgrade.message, 'From the server.');
    expect((await fail(503, 'busy')).retryable, isTrue);
    expect((await fail(409, 'in_progress')).retryable, isTrue);
    expect((await fail(429, 'rate_limited')).retryable, isTrue);
  });

  test('network failures and junk bodies become friendly errors', () async {
    final offline = ServerClient(
      baseUrl: Uri.parse('https://api.example.com'),
      token: () => 't',
      client: MockClient((_) async => throw http.ClientException('down')),
    );
    await expectLater(
      offline.me(),
      throwsA(isA<ApiError>().having((e) => e.offline, 'offline', isTrue)),
    );
    final junk = client((_) => http.Response('<html>', 200));
    await expectLater(junk.me(), throwsA(isA<ApiError>()));
  });

  test('photos follow signed links without our credentials', () async {
    final c = client((r) {
      if (r.url.host == 'photos.example.com') {
        return http.Response.bytes([9, 9], 200);
      }
      return http.Response(
        '',
        302,
        headers: {'location': 'https://photos.example.com/signed?x=1'},
      );
    });
    expect(await c.getPhoto('q_1_0'), [9, 9]);
    expect(requests.first.headers['authorization'], 'Bearer jws_token');
    expect(requests.last.headers.containsKey('authorization'), isFalse);
  });

  group('a draft whose request is cut off', () {
    DraftRequest request() => DraftRequest(
      profile: const BusinessProfile(name: 'Shine'),
      rates: const Rates(),
      photos: [
        JobPhoto(bytes: Uint8List.fromList([1, 2, 3]), mediaType: 'image/jpeg'),
      ],
    );

    ServerClient polling(http.Response Function(http.Request) reply) =>
        ServerClient(
          baseUrl: Uri.parse('https://api.example.com'),
          token: () => 'jws_token',
          draftPollEvery: Duration.zero,
          client: MockClient((r) async {
            requests.add(r);
            return reply(r);
          }),
        );

    test('is fetched by its key once the server finishes it', () async {
      var polls = 0;
      final c = polling((r) {
        if (r.method == 'POST') throw http.ClientException('connection closed');
        polls++;
        return polls == 1
            ? json(200, {'state': 'running'})
            : json(200, {
                'state': 'done',
                'draft': SampleJob.driveway.draft.toJson(),
                'model': 'claude-opus-5-5',
              });
      });
      final result = await c.draft(request(), idempotencyKey: 'draft_abc12345');
      expect(result.draft.items, isNotEmpty);
      expect(requests.map((r) => '${r.method} ${r.url.path}'), [
        'POST /v1/drafts',
        'GET /v1/drafts/draft_abc12345',
        'GET /v1/drafts/draft_abc12345',
      ]);
    });

    test('a proxy timeout, then a failed draft, asks to retry', () async {
      final c = polling(
        (r) => r.method == 'POST'
            ? http.Response('<html>Gateway Timeout</html>', 504)
            : json(200, {'state': 'failed'}),
      );
      await expectLater(
        c.draft(request(), idempotencyKey: 'draft_abc12345'),
        throwsA(
          isA<ApiError>().having(
            (e) => e.message,
            'message',
            contains("couldn't finish"),
          ),
        ),
      );
    });

    test('a request that never arrived keeps its own error', () async {
      final c = polling((r) {
        if (r.method == 'POST') throw http.ClientException('no signal');
        return json(404, {
          'error': {'code': 'not_found', 'message': 'No such draft.'},
        });
      });
      await expectLater(
        c.draft(request(), idempotencyKey: 'draft_abc12345'),
        throwsA(isA<ApiError>().having((e) => e.offline, 'offline', isTrue)),
      );
    });

    test('without a key there is nothing to ask about', () async {
      final c = polling((r) => throw http.ClientException('no signal'));
      await expectLater(c.draft(request()), throwsA(isA<ApiError>()));
      expect(requests, hasLength(1));
    });
  });
}
