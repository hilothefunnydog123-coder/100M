import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:shelf/shelf.dart';

import 'test_db.dart';

const webhookSecret = 'whsec_test_secret';
const adminToken = 'admin-token-for-tests-0123456789';
const browser =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 like Mac OS X) AppleWebKit/605.1.15';

ServerConfig testConfig({
  bool stripe = true,
  int trialDrafts = 25,
  int monthlyDraftCap = 500,
  String? metricsToken,
}) => ServerConfig(
  env: 'test',
  databaseUrl: TestDb.adminUrl,
  publicUrl: Uri.parse('https://jobwalk.test'),
  secret: 'test-secret-that-is-long-enough-0000000',
  drafter: const DrafterConfig(),
  stripeSecretKey: stripe ? 'sk_test_123' : null,
  stripeWebhookSecrets: stripe ? const [webhookSecret] : const [],
  stripePricePro: 'price_pro',
  stripePriceCrew: 'price_crew',
  adminToken: adminToken,
  metricsToken: metricsToken,
  trialDrafts: trialDrafts,
  monthlyDraftCap: monthlyDraftCap,
  reviewEmail: 'review@jobwalk.test',
  reviewCode: '424242',
  draftTimeout: const Duration(seconds: 5),
);

/// Drafts from the samples, or whatever [behavior] does.
class StubDrafter implements QuoteDrafter {
  Future<Draft> Function(DraftRequest request)? behavior;
  int calls = 0;

  @override
  Future<Draft> draft(DraftRequest request, {String? userId}) {
    calls++;
    final b = behavior;
    if (b != null) return b(request);
    final stats = DraftStats()
      ..inputTokens = 9000
      ..outputTokens = 6000
      ..models.add('claude-opus-5-5');
    return Future.value(
      Draft(
        SampleJob.forTrade(request.profile.primaryTrade).draft,
        stats,
        model: 'claude-opus-5-5',
      ),
    );
  }
}

/// Just enough of Stripe's API, with every request recorded.
class FakeStripe {
  final requests = <({String method, String path, Map<String, String> form})>[];
  final subscriptions = <String, Map<String, Object?>>{};
  final accounts = <String, Map<String, Object?>>{};
  int _n = 1000;

  List<Map<String, String>> posted(String path) => [
    for (final r in requests)
      if (r.method == 'POST' && r.path == path) r.form,
  ];

  void addSubscription(
    String id, {
    required String customer,
    String status = 'active',
    String price = 'price_pro',
    String? business,
  }) => subscriptions[id] = {
    'id': id,
    'status': status,
    'customer': customer,
    'items': {
      'data': [
        {
          'price': {'id': price},
        },
      ],
    },
    'metadata': {'business_id': ?business},
  };

  late final http.Client client = MockClient((request) async {
    final path = request.url.path;
    final form = request.method == 'POST' && request.body.isNotEmpty
        ? Uri.splitQueryString(request.body)
        : <String, String>{};
    requests.add((method: request.method, path: path, form: form));
    http.Response ok(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
    http.Response missing() => http.Response(
      jsonEncode({
        'error': {'type': 'invalid_request_error', 'message': 'No such object'},
      }),
      404,
    );
    final segments = request.url.pathSegments;
    switch ((request.method, path)) {
      case ('POST', '/v1/customers'):
        return ok({'id': 'cus_${_n++}'});
      case ('POST', '/v1/checkout/sessions'):
        final id = 'cs_test_${_n++}';
        return ok({'id': id, 'url': 'https://checkout.stripe.com/c/pay/$id'});
      case ('POST', '/v1/billing_portal/sessions'):
        return ok({'url': 'https://billing.stripe.com/p/session/test'});
      case ('POST', '/v1/accounts'):
        final id = 'acct_${_n++}abcdef';
        accounts[id] = {
          'id': id,
          'charges_enabled': false,
          'details_submitted': false,
        };
        return ok(accounts[id]!);
      case ('POST', '/v1/account_links'):
        return ok({
          'url': 'https://connect.stripe.com/setup/e/${form['account']}',
        });
    }
    if (segments.length == 3 && segments[1] == 'subscriptions') {
      final sub = subscriptions[segments[2]];
      if (sub == null) return missing();
      if (request.method == 'DELETE') sub['status'] = 'canceled';
      return ok(sub);
    }
    if (segments.length == 4 && segments[3] == 'login_links') {
      return ok({'url': 'https://connect.stripe.com/express/${segments[2]}'});
    }
    if (segments.length == 3 && segments[1] == 'accounts') {
      final account = accounts[segments[2]];
      return account == null ? missing() : ok(account);
    }
    return missing();
  });
}

/// The whole app on a test database, with a settable clock and fakes for
/// the model, email, storage, and Stripe.
class Harness {
  Harness(this.testDb, {ServerConfig? config, this.limits = Limits.relaxed})
    : config = config ?? testConfig();

  final TestDb testDb;
  final ServerConfig config;
  final Limits limits;
  Db get db => testDb.db;

  DateTime now = DateTime.utc(2026, 9, 25, 15);
  DateTime clock() => now;
  void advance(Duration d) => now = now.add(d);

  final emails = MemoryEmailSender();
  final store = MemoryObjectStore();
  final stripe = FakeStripe();
  final drafter = StubDrafter();
  final log = <Map<String, Object?>>[];

  late final app = JobwalkApp(
    config: config,
    db: db,
    drafter: drafter,
    email: emails,
    store: store,
    stripe: config.stripeEnabled
        ? StripeClient(secretKey: 'sk_test_123', client: stripe.client)
        : null,
    limits: limits,
    clock: clock,
    log: log.add,
  );

  AccountService get accounts => app.accounts;
  QuoteService get quotes => app.quotes;
  Outbox get outbox => app.outbox;

  Limiter generous() => MemoryLimiter(
    RateLimiter(
      capacity: 1000,
      refillEvery: const Duration(milliseconds: 1),
      clock: clock,
    ),
  );

  /// Runs every due background job.
  Future<int> runJobs() => app.worker.drain();

  /// The newest code emailed to [email].
  String lastCode(String email) {
    final to = email.trim().toLowerCase();
    final mail = emails.sent.lastWhere((m) => m.to == to);
    return RegExp(r'\b(\d{6})\b').firstMatch(mail.subject)!.group(1)!;
  }

  Future<SignIn> signIn(String email, {String ip = '203.0.113.7'}) async {
    await accounts.requestCode(email, ip: ip);
    await runJobs();
    return accounts.verifyCode(email, lastCode(email), ip: ip);
  }

  /// A signed-in owner whose business has a name, ready to quote.
  Future<SignIn> owner(
    String email, {
    String business = 'Brightline Painting',
  }) async {
    final s = await signIn(email);
    await accounts.updateBusiness(s.account, {
      'profile': {
        'name': business,
        'trades': ['painting'],
        'phone': '(512) 555-0142',
      },
      'rates': Rates.forTrade(Trade.painting).toJson(),
    });
    return s;
  }

  /// A quote as the phone makes it, from the living room sample.
  Quote sampleQuote({
    String? id,
    int number = 1042,
    String customer = 'Dana Ortiz',
  }) => QuoteBuilder.fromDraft(
    SampleJob.livingRoom.draft,
    id: id ?? newId('q'),
    number: number,
    rates: Rates.forTrade(Trade.painting),
    now: now,
    customer: Customer(name: customer, address: '12 Elm St'),
  );

  /// Syncs [quote] up and publishes it. Returns the public id.
  Future<String> sendQuote(Account a, Quote quote) async {
    await quotes.put(a, quote.id, {'quote': quote.toJson(), 'base_version': 0});
    final published = await quotes.publish(a, quote.id);
    final share = asMap(asMap(published['quote'])['share']);
    return share['public_id']! as String;
  }

  // -- HTTP ------------------------------------------------------------------

  Future<Response> send(
    String method,
    String path, {
    Object? body,
    String? token,
    Map<String, String> headers = const {},
  }) async {
    final Object? encoded = switch (body) {
      null => null,
      final String s => s,
      final Uint8List b => b,
      _ => jsonEncode(body),
    };
    return app.handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        body: encoded,
        headers: {
          if (body is Map || body is List) 'content-type': 'application/json',
          'authorization': ?(token == null ? null : 'Bearer $token'),
          'x-forwarded-for': '198.51.100.20',
          ...headers,
        },
      ),
    );
  }

  Future<Response> form(String path, Map<String, String> fields) => send(
    'POST',
    path,
    body: Uri(queryParameters: fields).query,
    headers: {
      'content-type': 'application/x-www-form-urlencoded',
      'user-agent': browser,
    },
  );

  Future<Response> stripeEvent(
    String type,
    Map<String, Object?> object, {
    String? id,
    String secret = webhookSecret,
  }) {
    final payload = jsonEncode({
      'id': id ?? 'evt_${DateTime.now().microsecondsSinceEpoch}',
      'type': type,
      'data': {'object': object},
    });
    return send(
      'POST',
      '/webhooks/stripe',
      body: payload,
      headers: {'stripe-signature': signStripePayload(payload, secret, now)},
    );
  }
}

Future<Map<String, Object?>> jsonOf(Response r) async =>
    jsonDecode(await r.readAsString()) as Map<String, Object?>;

/// Runs [fn] and returns the [ApiError] it throws.
Future<ApiError> apiError(Future<Object?> Function() fn) async {
  try {
    await fn();
  } on ApiError catch (e) {
    return e;
  }
  throw StateError('Expected an ApiError.');
}
