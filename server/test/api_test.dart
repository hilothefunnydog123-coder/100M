import 'dart:async';
import 'dart:convert';

import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'fakes.dart';

class StubDrafter implements QuoteDrafter {
  StubDrafter(this.behavior);

  Future<Draft> Function(DraftRequest request) behavior;
  int calls = 0;
  String? lastUserId;

  @override
  Future<Draft> draft(DraftRequest request, {String? userId}) {
    calls++;
    lastUserId = userId;
    return behavior(request);
  }
}

Future<Draft> sample(DraftRequest request) =>
    DemoDrafter(delay: Duration.zero).draft(request);

const installId = 'install_abc123';
const browser =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 like Mac OS X) AppleWebKit/605.1.15';

void main() {
  late StubDrafter drafter;
  late MemoryQuoteStore store;
  late MemoryWaitlistStore waitlist;
  late List<Map<String, Object?>> logs;
  late DateTime clock;
  late JobwalkApi api;

  JobwalkApi build({
    int installBurst = 10,
    int ipBurst = 100,
    ConcurrencyLimiter? concurrency,
    Duration timeout = const Duration(seconds: 170),
    Uri? publicBaseUrl,
  }) => JobwalkApi(
    drafter: drafter,
    quotes: store,
    waitlist: waitlist,
    installLimiter: RateLimiter(
      capacity: installBurst,
      refillEvery: const Duration(minutes: 10),
    ),
    ipLimiter: RateLimiter(
      capacity: ipBurst,
      refillEvery: const Duration(minutes: 10),
    ),
    concurrency:
        concurrency ?? ConcurrencyLimiter(maxConcurrent: 4, maxQueued: 4),
    model: 'claude-opus-5-5',
    draftTimeout: timeout,
    publicBaseUrl: publicBaseUrl,
    log: logs.add,
    clock: () => clock,
  );

  setUp(() {
    drafter = StubDrafter(sample);
    store = MemoryQuoteStore();
    waitlist = MemoryWaitlistStore();
    logs = [];
    clock = now;
    api = build();
  });

  Future<Response> send(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
    JobwalkApi? using,
  }) async => (using ?? api).handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body == null
          ? null
          : body is String
          ? body
          : jsonEncode(body),
      headers: {
        if (body != null && body is! String) 'content-type': 'application/json',
        ...headers,
      },
    ),
  );

  Future<Response> form(String path, Map<String, String> fields) => send(
    'POST',
    path,
    body: Uri(queryParameters: fields).query,
    headers: {'content-type': 'application/x-www-form-urlencoded'},
  );

  Future<Map<String, Object?>> jsonOf(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  Future<({String id, String token, String url})> publish([
    PublicQuote? quote,
  ]) async {
    final r = await send(
      'POST',
      '/v1/quotes',
      body: {'quote': (quote ?? publicQuote()).toJson()},
    );
    expect(r.statusCode, 201);
    final j = await jsonOf(r);
    return (
      id: j['id']! as String,
      token: j['owner_token']! as String,
      url: j['url']! as String,
    );
  }

  Future<Map<String, Object?>> status(String id, String token) async {
    final r = await send(
      'GET',
      '/v1/quotes/$id',
      headers: {'authorization': 'Bearer $token'},
    );
    expect(r.statusCode, 200);
    return (await jsonOf(r))['response']! as Map<String, Object?>;
  }

  Future<Response> view(String id, {String userAgent = browser}) =>
      send('GET', '/q/$id', headers: {'user-agent': userAgent});

  group('drafts', () {
    Future<Response> draft({
      Object? body,
      Map<String, String> headers = const {'x-install-id': installId},
      JobwalkApi? using,
    }) => send(
      'POST',
      '/v1/drafts',
      body: body ?? draftRequest().toJson(),
      headers: headers,
      using: using,
    );

    test('returns a parsed draft', () async {
      final r = await draft();
      expect(r.statusCode, 200);
      final j = await jsonOf(r);
      expect(j['demo'], isTrue);
      final d = AiDraft.fromJson(j['draft']! as Map<String, Object?>);
      expect(d.isUsable, isTrue);
      expect(drafter.lastUserId, installId);
      final log = logs.singleWhere((l) => l['event'] == 'draft');
      expect(log['lines'], d.items.length);
      expect(jsonEncode(log), isNot(contains('cedar')));
    });

    test('requires an install id', () async {
      final r = await draft(headers: const {});
      expect(r.statusCode, 400);
      expect(drafter.calls, 0);
    });

    test('rejects bad bodies before calling the model', () async {
      expect((await draft(body: 'not json')).statusCode, 400);
      final r = await draft(body: {'photos': <Object?>[]});
      expect(r.statusCode, 400);
      expect(((await jsonOf(r))['error'] as Map)['code'], 'invalid_request');
      expect(drafter.calls, 0);
    });

    test('rate limits per install', () async {
      final limited = build(installBurst: 1);
      expect((await draft(using: limited)).statusCode, 200);
      final r = await draft(using: limited);
      expect(r.statusCode, 429);
      expect(r.headers['retry-after'], isNotNull);
    });

    test('maps failures to status codes', () async {
      drafter.behavior = (_) async =>
          throw DraftFailed('refused', refused: true);
      expect((await draft()).statusCode, 422);

      drafter.behavior = (_) async => throw DraftFailed(
        'busy',
        cause: ClaudeApiException(529, 'overloaded_error', 'Overloaded'),
      );
      final busy = await draft();
      expect(busy.statusCode, 503);
      expect(busy.headers['retry-after'], '30');

      drafter.behavior = (_) async => throw DraftFailed(
        'bad',
        cause: ClaudeApiException(400, 'invalid_request_error', 'Bad'),
      );
      expect((await draft()).statusCode, 502);
    });

    test('times out', () async {
      drafter.behavior = (_) => Completer<Draft>().future;
      final r = await draft(
        using: build(timeout: const Duration(milliseconds: 10)),
      );
      expect(r.statusCode, 504);
    });

    test('sheds load when the queue is full', () async {
      final gate = Completer<void>();
      drafter.behavior = (request) async {
        await gate.future;
        return sample(request);
      };
      final tight = build(
        concurrency: ConcurrencyLimiter(maxConcurrent: 1, maxQueued: 0),
      );
      final first = draft(using: tight);
      await Future<void>.delayed(Duration.zero);
      expect((await draft(using: tight)).statusCode, 503);
      gate.complete();
      expect((await first).statusCode, 200);
    });
  });

  group('publishing', () {
    test('returns a link and a token that reads status', () async {
      final q = await publish();
      expect(q.url, 'http://localhost/q/${q.id}');
      expect(q.id, matches(RegExp(r'^[a-z0-9]{16}$')));
      expect(q.token.length, 40);
      final s = await status(q.id, q.token);
      expect(s['views'], 0);
      // Only a hash of the token is stored.
      expect(
        jsonEncode(store.records[q.id]!.toJson()),
        isNot(contains(q.token)),
      );
    });

    test('uses the configured public URL', () async {
      api = build(publicBaseUrl: Uri.parse('https://jobwalk.app'));
      final q = await publish();
      expect(q.url, 'https://jobwalk.app/q/${q.id}');
    });

    test('rejects oversized bodies', () async {
      final r = await send(
        'POST',
        '/v1/quotes',
        body: 'x' * (JobwalkApi.maxQuoteBodyBytes + 1),
        headers: {'content-type': 'application/json'},
      );
      expect(r.statusCode, 413);
    });

    test('rejects quotes whose totals do not add up', () async {
      final json = publicQuote().toJson();
      ((json['options'] as List).first as Map)['total_cents'] = 1;
      final r = await send('POST', '/v1/quotes', body: {'quote': json});
      expect(r.statusCode, 400);
      expect(((await jsonOf(r))['error'] as Map)['code'], 'invalid_quote');
      expect(store.records, isEmpty);
    });

    test('status needs the right token', () async {
      final q = await publish();
      for (final headers in [
        <String, String>{},
        {'authorization': 'Bearer wrong'},
        {'authorization': q.token},
      ]) {
        final r = await send('GET', '/v1/quotes/${q.id}', headers: headers);
        expect(r.statusCode, 404);
      }
      final missing = await send(
        'GET',
        '/v1/quotes/nope',
        headers: {'authorization': 'Bearer ${q.token}'},
      );
      expect(missing.statusCode, 404);
    });

    test('updates bump the revision and need the token', () async {
      final q = await publish();
      final body = {'quote': publicQuote(business: 'Brightline Co.').toJson()};
      final denied = await send('PUT', '/v1/quotes/${q.id}', body: body);
      expect(denied.statusCode, 404);
      final r = await send(
        'PUT',
        '/v1/quotes/${q.id}',
        body: body,
        headers: {'authorization': 'Bearer ${q.token}'},
      );
      expect(r.statusCode, 200);
      expect((await jsonOf(r))['revision'], 2);
      expect(store.records[q.id]!.quote.business.name, 'Brightline Co.');
    });
  });

  group('customer page', () {
    test('shows the quote and counts real views', () async {
      final q = await publish();
      final r = await view(q.id);
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], contains('text/html'));
      expect(
        r.headers['content-security-policy'],
        contains("default-src 'none'"),
      );
      expect(r.headers['referrer-policy'], 'no-referrer');
      final html = await r.readAsString();
      expect(html, contains('Brightline Painting'));
      expect(html, contains('Walls + trim'));
      expect(html, contains(r'$1,245'));
      expect(html, contains('Approve Walls + trim: \$1,245'));
      expect(html, contains('Recommended'));

      clock = now.add(const Duration(hours: 1));
      await view(q.id);
      final s = await status(q.id, q.token);
      expect(s['views'], 2);
      expect(s['first_viewed_at'], now.toIso8601String());
      expect(s['last_viewed_at'], clock.toIso8601String());
    });

    test('link previews and owner previews are not views', () async {
      final q = await publish();
      await view(q.id, userAgent: 'facebookexternalhit/1.1 Facebot Twitterbot');
      await view(q.id, userAgent: 'WhatsApp/2.23');
      await send(
        'GET',
        '/q/${q.id}?preview=1',
        headers: {'user-agent': browser},
      );
      expect((await status(q.id, q.token))['views'], 0);
    });

    test('escapes everything the contractor typed', () async {
      final q = await publish(
        publicQuote(business: '<script>alert(1)</script>'),
      );
      final html = await (await view(q.id)).readAsString();
      expect(html, isNot(contains('<script>alert(1)')));
      expect(html, contains('&lt;script&gt;'));
    });

    test('unknown quotes are a friendly 404', () async {
      final r = await view('abcdefghijkmnpqr');
      expect(r.statusCode, 404);
      expect(await r.readAsString(), contains('Quote not found'));
      expect((await view('../../etc/passwd')).statusCode, 404);
    });

    test('the sample quote cannot be approved', () async {
      final r = await send('GET', '/sample');
      expect(r.statusCode, 200);
      final html = await r.readAsString();
      expect(html, contains('This is a sample quote'));
      expect(html, isNot(contains('<form method="post"')));
    });
  });

  group('approval', () {
    test('records the option and signature', () async {
      final q = await publish(
        publicQuote(paymentLink: 'https://buy.stripe.com/test_1'),
      );
      clock = now.add(const Duration(hours: 2));
      final r = await form('/q/${q.id}/approve', {
        'option': 'full_room',
        'name': 'Dana Ortiz',
        'agree': 'yes',
      });
      expect(r.statusCode, 303);
      expect(r.headers['location'], '/q/${q.id}?preview=1&done=approved');

      final s = await status(q.id, q.token);
      expect(s['approved_option'], 'full_room');
      expect(s['signature'], 'Dana Ortiz');
      expect(s['approved_at'], clock.toIso8601String());

      final html = await (await send(
        'GET',
        r.headers['location']!,
      )).readAsString();
      expect(html, contains('Approved Sep 25, 2026 by Dana Ortiz'));
      expect(html, contains(r'Pay the $353 deposit'));
      expect(html, isNot(contains('name="agree"')));
    });

    test('explains what is missing', () async {
      final q = await publish();
      Future<String?> attempt(Map<String, String> fields) async =>
          (await form('/q/${q.id}/approve', fields)).headers['location'];

      expect(
        await attempt({'option': 'walls', 'agree': 'yes'}),
        endsWith('error=name#approve'),
      );
      expect(
        await attempt({'option': 'walls', 'name': 'Dana'}),
        endsWith('error=agree#approve'),
      );
      expect(
        await attempt({'option': 'gold', 'name': 'Dana', 'agree': 'yes'}),
        endsWith('error=option#approve'),
      );
      expect((await status(q.id, q.token))['approved_at'], isNull);
      final html = await (await send(
        'GET',
        '/q/${q.id}?preview=1&error=agree',
      )).readAsString();
      expect(html, contains('Check the box to approve the quote.'));
    });

    test('is final: no second approval, no edits', () async {
      final q = await publish();
      await form('/q/${q.id}/approve', {
        'option': 'walls',
        'name': 'Dana',
        'agree': 'yes',
      });
      await form('/q/${q.id}/approve', {
        'option': 'full_room',
        'name': 'Someone else',
        'agree': 'yes',
      });
      expect((await status(q.id, q.token))['approved_option'], 'walls');

      final r = await send(
        'PUT',
        '/v1/quotes/${q.id}',
        body: {'quote': publicQuote().toJson()},
        headers: {'authorization': 'Bearer ${q.token}'},
      );
      expect(r.statusCode, 409);
    });

    test('expired quotes cannot be approved', () async {
      final q = await publish();
      clock = now.add(const Duration(days: 31));
      await form('/q/${q.id}/approve', {
        'option': 'walls',
        'name': 'Dana',
        'agree': 'yes',
      });
      expect((await status(q.id, q.token))['approved_at'], isNull);
      final html = await (await view(q.id)).readAsString();
      expect(html, contains('This quote expired on Oct 25, 2026'));
    });
  });

  group('decline', () {
    test('records the reason; a revision clears it', () async {
      final q = await publish();
      final r = await form('/q/${q.id}/decline', {
        'reason': 'Went with a friend',
      });
      expect(r.statusCode, 303);
      var s = await status(q.id, q.token);
      expect(s['declined_at'], isNotNull);
      expect(s['decline_reason'], 'Went with a friend');

      await send(
        'PUT',
        '/v1/quotes/${q.id}',
        body: {'quote': publicQuote().toJson()},
        headers: {'authorization': 'Bearer ${q.token}'},
      );
      s = await status(q.id, q.token);
      expect(s['declined_at'], isNull);
    });

    test('cannot undo an approval', () async {
      final q = await publish();
      await form('/q/${q.id}/approve', {
        'option': 'walls',
        'name': 'Dana',
        'agree': 'yes',
      });
      await form('/q/${q.id}/decline', {'reason': 'changed my mind'});
      final s = await status(q.id, q.token);
      expect(s['approved_at'], isNotNull);
      expect(s['declined_at'], isNull);
    });
  });

  group('landing and waitlist', () {
    test('landing page', () async {
      final r = await send('GET', '/');
      expect(r.statusCode, 200);
      final html = await r.readAsString();
      expect(html, contains('Quote the job before you leave the driveway.'));
      expect(html, isNot(contains('noindex')));
    });

    test('form signups redirect and are stored', () async {
      final r = await form('/waitlist', {
        'email': ' Mike@Example.com ',
        'trade': 'fencing',
        'crew': '2-5',
      });
      expect(r.statusCode, 303);
      expect(r.headers['location'], '/?joined=1#join');
      final e = waitlist.entries.single;
      expect(e.email, 'mike@example.com');
      expect(e.trade, 'fencing');
      expect(e.crew, '2-5');
      final page = await (await send('GET', '/?joined=1')).readAsString();
      expect(page, contains("You're on the list"));
    });

    test('bad emails are rejected; unknown fields are dropped', () async {
      final r = await form('/waitlist', {'email': 'nope'});
      expect(r.statusCode, 400);
      expect(await r.readAsString(), contains('Enter a valid email'));
      final ok = await send(
        'POST',
        '/waitlist',
        body: {'email': 'a@b.co', 'trade': 'astronaut', 'crew': '900'},
      );
      expect(ok.statusCode, 200);
      expect(waitlist.entries.single.trade, '');
      expect(waitlist.entries.single.crew, '');
    });

    test('writes are rate limited per IP', () async {
      api = build(ipBurst: 2);
      for (var i = 0; i < 2; i++) {
        expect(
          (await form('/waitlist', {'email': 'a$i@b.co'})).statusCode,
          303,
        );
      }
      expect((await form('/waitlist', {'email': 'c@b.co'})).statusCode, 429);
    });
  });

  test('CORS applies to the API only', () async {
    final preflight = await send(
      'OPTIONS',
      '/v1/drafts',
      headers: {'origin': 'https://app.jobwalk.app'},
    );
    expect(preflight.statusCode, 204);
    expect(
      preflight.headers['access-control-allow-headers'],
      contains('authorization'),
    );
    final page = await send(
      'GET',
      '/',
      headers: {'origin': 'https://evil.example'},
    );
    expect(page.headers['access-control-allow-origin'], isNull);
  });

  test('health', () async {
    final j = await jsonOf(await send('GET', '/healthz'));
    expect(j['ok'], isTrue);
    expect(j['prompt_version'], promptVersion);
  });
}
