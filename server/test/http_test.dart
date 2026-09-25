import 'dart:convert';
import 'dart:typed_data';

import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'fakes.dart' show draftRequest;
import 'support/harness.dart';
import 'support/test_db.dart';

void main() {
  withDb((testDb) {
    late Harness h;
    setUp(() => h = Harness(testDb()));

    /// Signs in over HTTP, as the app does.
    Future<String> signIn(String email) async {
      final code = await h.send(
        'POST',
        '/v1/auth/code',
        body: {'email': email},
      );
      expect(code.statusCode, 200);
      await h.runJobs();
      final verify = await h.send(
        'POST',
        '/v1/auth/verify',
        body: {'email': email, 'code': h.lastCode(email), 'device': 'Pixel 9'},
      );
      expect(verify.statusCode, 200);
      final body = await jsonOf(verify);
      expect(body['user'], containsPair('email', email));
      return body['token']! as String;
    }

    Future<String> owner(String email) async {
      final token = await signIn(email);
      final r = await h.send(
        'PUT',
        '/v1/business',
        token: token,
        body: {
          'profile': {
            'name': 'Brightline <Painting>',
            'trades': ['painting'],
          },
          'rates': Rates.forTrade(Trade.painting).toJson(),
        },
      );
      expect(r.statusCode, 200);
      return token;
    }

    Future<String> publish(String token, {Quote? quote}) async {
      final q = quote ?? h.sampleQuote();
      final put = await h.send(
        'PUT',
        '/v1/quotes/${q.id}',
        token: token,
        body: {'quote': q.toJson(), 'base_version': 0},
      );
      expect(put.statusCode, 200);
      final pub = await h.send(
        'POST',
        '/v1/quotes/${q.id}/publish',
        token: token,
      );
      expect(pub.statusCode, 200);
      final share = ((await jsonOf(pub))['quote']! as Map)['share']! as Map;
      return share['public_id']! as String;
    }

    group('API', () {
      test('sign in, read the account, sign out', () async {
        final token = await signIn('dana@example.com');
        final me = await h.send('GET', '/v1/me', token: token);
        expect(me.statusCode, 200);
        final body = await jsonOf(me);
        expect((body['business']! as Map)['setup_complete'], isFalse);

        final out = await h.send('POST', '/v1/auth/sign-out', token: token);
        expect(out.statusCode, 200);
        expect((await h.send('GET', '/v1/me', token: token)).statusCode, 401);
      });

      test('errors are JSON with a stable code and the request id', () async {
        final r = await h.send(
          'GET',
          '/v1/me',
          headers: {'x-request-id': 'req-from-phone-1'},
        );
        expect(r.statusCode, 401);
        expect(r.headers['x-request-id'], 'req-from-phone-1');
        expect(await jsonOf(r), {
          'error': {
            'code': 'unauthorized',
            'message': 'Sign in again to continue.',
            'request_id': 'req-from-phone-1',
          },
        });
        final generated = await h.send('GET', '/v1/nope');
        expect(generated.statusCode, 404);
        expect(generated.headers['x-request-id'], hasLength(20));
        expect(generated.mimeType, 'application/json');
      });

      test('rejects bad bodies', () async {
        final token = await signIn('dana@example.com');
        final bad = await h.send(
          'PUT',
          '/v1/business',
          token: token,
          body: '{not json',
          headers: {'content-type': 'application/json'},
        );
        expect(bad.statusCode, 400);
        expect(
          (await jsonOf(bad))['error'],
          containsPair('code', 'invalid_json'),
        );

        final huge = await h.send(
          'PUT',
          '/v1/quotes/q_big0000000000000000',
          token: token,
          body: {'quote': 'x' * (600 * 1024)},
        );
        expect(huge.statusCode, 413);
      });

      test('quote sync round trip over HTTP', () async {
        final token = await owner('dana@example.com');
        final q = h.sampleQuote();
        await h.send(
          'PUT',
          '/v1/quotes/${q.id}',
          token: token,
          body: {'quote': q.toJson(), 'base_version': 0},
        );
        final changes = await jsonOf(
          await h.send('GET', '/v1/quotes?since=0&limit=10', token: token),
        );
        expect((changes['items']! as List).single, containsPair('id', q.id));
        final conflict = await h.send(
          'PUT',
          '/v1/quotes/${q.id}',
          token: token,
          body: {
            'quote': q.copyWith(title: 'x').toJson(),
            'base_version': 0,
          },
        );
        expect(conflict.statusCode, 409);
        final body = await jsonOf(conflict);
        expect(body['error'], containsPair('code', 'conflict'));
        expect(body['current'], containsPair('version', 1));
        final deleted = await h.send(
          'DELETE',
          '/v1/quotes/${q.id}',
          token: token,
        );
        expect((await jsonOf(deleted))['deleted'], isTrue);
      });

      test('photos upload once and come back', () async {
        final token = await owner('dana@example.com');
        final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 9, 9, 9]);
        final put = await h.send(
          'PUT',
          '/v1/photos/q_abc_0',
          token: token,
          body: bytes,
          headers: {'content-type': 'image/jpeg'},
        );
        expect(put.statusCode, 201);
        await h.send(
          'PUT',
          '/v1/photos/q_abc_0',
          token: token,
          body: bytes,
          headers: {'content-type': 'image/jpeg'},
        );
        final get = await h.send('GET', '/v1/photos/q_abc_0', token: token);
        expect(get.statusCode, 200);
        expect(get.mimeType, 'image/jpeg');
        expect(await get.read().expand((c) => c).toList(), bytes);

        final notImage = await h.send(
          'PUT',
          '/v1/photos/q_abc_1',
          token: token,
          body: Uint8List.fromList(utf8.encode('<svg onload=alert(1)>')),
        );
        expect(notImage.statusCode, 415);

        final other = await owner('sam@example.com');
        expect(
          (await h.send('GET', '/v1/photos/q_abc_0', token: other)).statusCode,
          404,
        );
      });

      test('drafts over HTTP, with an idempotency key', () async {
        final token = await owner('dana@example.com');
        final body = draftRequest().toJson();
        final first = await h.send(
          'POST',
          '/v1/drafts',
          token: token,
          body: body,
          headers: {
            'content-type': 'application/json',
            'idempotency-key': 'key-000001',
          },
        );
        expect(first.statusCode, 200);
        final again = await h.send(
          'POST',
          '/v1/drafts',
          token: token,
          body: body,
          headers: {
            'content-type': 'application/json',
            'idempotency-key': 'key-000001',
          },
        );
        expect((await jsonOf(again))['replayed'], isTrue);
        expect(h.drafter.calls, 1);

        final invalid = await h.send(
          'POST',
          '/v1/drafts',
          token: token,
          body: {'photos': <Object>[]},
        );
        expect(invalid.statusCode, 400);
        expect(h.drafter.calls, 1);
      });

      test('team and account endpoints', () async {
        final token = await owner('dana@example.com');
        final add = await h.send(
          'POST',
          '/v1/team',
          token: token,
          body: {'email': 'lee@example.com', 'name': 'Lee'},
        );
        expect(add.statusCode, 201);
        final numbers = await jsonOf(
          await h.send(
            'POST',
            '/v1/business/numbers',
            token: token,
            body: {'count': 3, 'at_least': 1050},
          ),
        );
        expect(numbers, {'first': 1050, 'count': 3});
        final export = await h.send('GET', '/v1/account/export', token: token);
        expect(export.headers['content-disposition'], contains('attachment'));
        expect((await jsonOf(export))['users'], hasLength(2));
        final delete = await h.send(
          'DELETE',
          '/v1/account',
          token: token,
          body: {'confirm': 'DELETE'},
        );
        expect(delete.statusCode, 200);
        expect((await h.send('GET', '/v1/me', token: token)).statusCode, 401);
      });

      test('billing endpoints', () async {
        final token = await owner('dana@example.com');
        final checkout = await h.send(
          'POST',
          '/v1/billing/checkout',
          token: token,
          body: {'plan': 'pro'},
        );
        expect(checkout.statusCode, 200);
        expect(
          (await jsonOf(checkout))['url'],
          contains('checkout.stripe.com'),
        );
        final payments = await jsonOf(
          await h.send('GET', '/v1/payments', token: token),
        );
        expect(payments['enabled'], isTrue);
        expect(payments['connected'], isFalse);
      });

      test('CORS applies to the API only', () async {
        final preflight = await h.send(
          'OPTIONS',
          '/v1/me',
          headers: {
            'origin': 'https://app.jobwalk.test',
            'access-control-request-method': 'GET',
          },
        );
        expect(preflight.statusCode, 204);
        expect(preflight.headers['access-control-allow-origin'], '*');
        expect(
          preflight.headers['access-control-allow-headers'],
          contains('idempotency-key'),
        );
        final page = await h.send(
          'GET',
          '/',
          headers: {'origin': 'https://evil.example'},
        );
        expect(page.headers['access-control-allow-origin'], isNull);
        // Errors carry CORS headers too, so the web app can read them.
        final error = await h.send(
          'GET',
          '/v1/me',
          headers: {'origin': 'https://app.jobwalk.test'},
        );
        expect(error.statusCode, 401);
        expect(error.headers['access-control-allow-origin'], '*');
      });
    });

    group('customer page', () {
      test('shows the quote, counts real visits, escapes text', () async {
        final token = await owner('dana@example.com');
        final q = h.sampleQuote().copyWith(
          customer: const Customer(name: '<script>alert(1)</script>'),
        );
        final id = await publish(token, quote: q);
        final r = await h.send(
          'GET',
          '/q/$id',
          headers: {'user-agent': browser},
        );
        expect(r.statusCode, 200);
        expect(
          r.headers['content-security-policy'],
          contains("default-src 'none'"),
        );
        expect(r.headers['x-robots-tag'], contains('noindex'));
        expect(r.headers['referrer-policy'], 'no-referrer');
        final html = await r.readAsString();
        expect(html, contains('Brightline &lt;Painting&gt;'));
        expect(html, isNot(contains('<script>alert')));
        expect(html, contains('Approve'));

        // Link previews don't count.
        await h.send(
          'GET',
          '/q/$id',
          headers: {'user-agent': 'WhatsApp/2.23.20.0'},
        );
        final view = await h.quotes.open(id, countView: false);
        expect(view!.response.views, 1);
      });

      test('approve with the form, then it is final', () async {
        final token = await owner('dana@example.com');
        final id = await publish(token);
        final missing = await h.form('/q/$id/approve', {
          'option': 'walls_trim',
          'name': 'Dana Ortiz',
        });
        expect(missing.statusCode, 303);
        expect(
          missing.headers['location'],
          '/q/$id?preview=1&error=agree#approve',
        );
        final errorPage = await (await h.send(
          'GET',
          '/q/$id?preview=1&error=agree',
        )).readAsString();
        expect(errorPage, contains('Check the box to approve'));

        final ok = await h.form('/q/$id/approve', {
          'option': 'walls_trim',
          'name': 'Dana Ortiz',
          'agree': 'yes',
        });
        expect(ok.statusCode, 303);
        final page = await (await h.send(
          'GET',
          ok.headers['location']!,
        )).readAsString();
        expect(page, contains('Approved'));
        expect(page, contains('by Dana Ortiz'));
        expect(page, isNot(contains('name="agree"')));

        final event =
            (await h.db.one(
                  "SELECT data FROM quote_events WHERE kind = 'approved'",
                ))!['data']
                as Map;
        expect(event['ip'], '198.51.100.20');
      });

      test('decline with a reason', () async {
        final token = await owner('dana@example.com');
        final id = await publish(token);
        final r = await h.form('/q/$id/decline', {'reason': 'Too soon'});
        expect(r.headers['location'], '/q/$id?preview=1&done=declined');
        final page = await (await h.send(
          'GET',
          r.headers['location']!,
        )).readAsString();
        expect(page, contains('Thanks for letting us know'));
      });

      test('unknown quotes are a friendly 404 page', () async {
        final r = await h.send('GET', '/q/doesnotexist0000');
        expect(r.statusCode, 404);
        expect(r.mimeType, 'text/html');
        expect(await r.readAsString(), contains('Page not found'));
        expect(
          (await h.form('/q/doesnotexist0000/approve', {})).statusCode,
          404,
        );
      });

      test('the sample quote cannot be approved', () async {
        final html = await (await h.send('GET', '/sample')).readAsString();
        expect(html, contains('This is a sample quote'));
        expect(html, isNot(contains('name="agree"')));
      });

      test('form posts are rate limited per address', () async {
        final strict = Harness(
          testDb(),
          limits: const Limits(publicPerIp: (2, Duration(minutes: 10))),
        );
        for (var i = 0; i < 2; i++) {
          expect(
            (await strict.form('/waitlist', {
              'email': 'a$i@example.com',
            })).statusCode,
            303,
          );
        }
        final limited = await strict.form('/waitlist', {
          'email': 'c@example.com',
        });
        expect(limited.statusCode, 429);
        expect(limited.headers['retry-after'], isNotNull);
      });
    });

    group('site', () {
      test('landing page and waitlist', () async {
        final landing = await h.send('GET', '/');
        expect(landing.statusCode, 200);
        expect(await landing.readAsString(), contains('Jobwalk'));

        final joined = await h.form('/waitlist', {
          'email': ' Pat@Example.com ',
          'trade': 'painting',
          'crew': '2-5',
          'extra': 'ignored',
        });
        expect(joined.headers['location'], '/?joined=1#join');
        final json = await h.send(
          'POST',
          '/waitlist',
          body: {'email': 'lee@example.com', 'trade': 'nonsense'},
        );
        expect(json.statusCode, 200);
        final bad = await h.form('/waitlist', {'email': 'nope'});
        expect(bad.statusCode, 400);
        final rows = await h.db.query(
          'SELECT email, trade, crew FROM waitlist ORDER BY email',
        );
        expect(rows, [
          {'email': 'lee@example.com', 'trade': '', 'crew': ''},
          {'email': 'pat@example.com', 'trade': 'painting', 'crew': '2-5'},
        ]);
      });

      test('health, readiness, robots', () async {
        final health = await jsonOf(await h.send('GET', '/healthz'));
        expect(health['ok'], isTrue);
        expect(health['prompt_version'], promptVersion);
        final ready = await h.send('GET', '/readyz');
        expect(ready.statusCode, 200);
        expect(
          await jsonOf(ready),
          containsPair('schema', latestSchemaVersion),
        );
        final robots = await (await h.send(
          'GET',
          '/robots.txt',
        )).readAsString();
        expect(robots, contains('Disallow: /q/'));
      });

      test('metrics need the token when one is set', () async {
        final secured = Harness(
          testDb(),
          config: testConfig(metricsToken: 'metrics-token'),
        );
        await secured.send('GET', '/');
        expect((await secured.send('GET', '/metrics')).statusCode, 404);
        final r = await secured.send('GET', '/metrics', token: 'metrics-token');
        expect(r.statusCode, 200);
        final text = await r.readAsString();
        expect(
          text,
          contains(
            'jobwalk_http_requests_total{method="GET",route="/",status="200"} 1',
          ),
        );
        expect(
          text,
          contains(
            '# TYPE jobwalk_http_request_duration_seconds '
            'histogram',
          ),
        );
      });

      test('admin endpoints hide without the token', () async {
        await owner('dana@example.com');
        await h.form('/waitlist', {'email': '=cmd@example.com'});
        expect((await h.send('GET', '/admin/stats')).statusCode, 404);
        expect(
          (await h.send('GET', '/admin/stats', token: 'wrong')).statusCode,
          404,
        );
        final stats = await jsonOf(
          await h.send('GET', '/admin/stats', token: adminToken),
        );
        expect(stats['businesses'], 1);
        expect(stats['waitlist'], 1);
        expect(stats['plans'], [
          {'plan': 'trial', 'status': 'trialing', 'businesses': 1},
        ]);
        final csv = await (await h.send(
          'GET',
          '/admin/waitlist.csv',
          token: adminToken,
        )).readAsString();
        expect(csv, contains('"\'=cmd@example.com"'));
      });

      test('failed jobs can be listed and retried', () async {
        await h.db.execute(
          'INSERT INTO jobs (kind, payload, failed, done_at, last_error) '
          "VALUES ('email.send', '{}', true, now(), 'boom')",
        );
        final jobs = await jsonOf(
          await h.send('GET', '/admin/jobs', token: adminToken),
        );
        final job = (jobs['jobs']! as List).single as Map;
        expect(job['last_error'], 'boom');
        final retry = await h.send(
          'POST',
          '/admin/jobs/${job['id']}/retry',
          token: adminToken,
        );
        expect(retry.statusCode, 200);
        final row = (await h.db.one('SELECT failed, done_at FROM jobs'))!;
        expect(row['failed'], isFalse);
        expect(row['done_at'], isNull);
      });

      test('while draining, new requests get 503', () async {
        h.app.draining = true;
        final r = await h.send('GET', '/v1/me');
        expect(r.statusCode, 503);
        expect((await h.send('GET', '/healthz')).statusCode, 200);
      });

      test('unexpected errors are logged and hidden', () async {
        await h.db.execute('DROP TABLE waitlist');
        final r = await h.send(
          'POST',
          '/waitlist',
          body: {'email': 'a@example.com'},
        );
        expect(r.statusCode, 500);
        final body = await r.readAsString();
        expect(body, isNot(contains('waitlist')));
        expect(
          h.log.where((e) => e['event'] == 'error').single['error'],
          contains('waitlist'),
        );
        await h.db.script(
          'CREATE TABLE waitlist (email text PRIMARY KEY, trade text NOT NULL '
          "DEFAULT '', crew text NOT NULL DEFAULT '', created_at timestamptz "
          'NOT NULL DEFAULT now())',
        );
      });
    });

    test('every request is logged without personal data', () async {
      await signIn('dana@example.com');
      final requests = h.log.where((e) => e['event'] == 'request').toList();
      expect(requests, isNotEmpty);
      expect(jsonEncode(h.log), isNot(contains('dana@example.com')));
      expect(requests.first.keys, containsAll(['id', 'route', 'status', 'ms']));
    });

    test('a real request passes the security headers', () async {
      final r = await h.app.handler(
        Request('GET', Uri.parse('http://localhost/')),
      );
      expect(r.headers['x-content-type-options'], 'nosniff');
      expect(r.headers['x-frame-options'], 'DENY');
    });
  });
}
