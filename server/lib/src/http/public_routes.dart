import 'dart:convert';

import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../common.dart';
import '../db/database.dart';
import '../db/migrations.dart';
import '../integrations/stripe.dart' show constantTimeEquals;
import '../limits.dart';
import '../metrics.dart';
import '../pages.dart';
import '../prompt.dart';
import '../services/billing.dart';
import '../services/quotes.dart';
import 'respond.dart';

/// Pages people open in a browser, webhooks, and health checks.
class PublicRoutes {
  PublicRoutes({
    required Db db,
    required this.quotes,
    required this.billing,
    required this.perIp,
    required this.viewsPerVisitor,
    required this.metrics,
    required this.model,
    required this.version,
    this.metricsToken,
    this.exposeMetrics = false,
    this.trustedProxies = 1,
    Clock clock = systemClock,
    LogSink? log,
  }) : _db = db,
       _clock = clock,
       _log = log ?? ((_) {});

  final QuoteService quotes;
  final BillingService billing;

  /// Customer form posts and signups per address.
  final Limiter perIp;

  /// How often one visitor's visits to a quote count as views, so a
  /// refresh isn't a second view and repeated hits can't pile up writes.
  final Limiter viewsPerVisitor;
  final Metrics metrics;
  final String model;
  final String version;

  /// With a token, /metrics needs `Authorization: Bearer <token>`.
  final String? metricsToken;

  /// Serve /metrics without a token (development).
  final bool exposeMetrics;
  final int trustedProxies;
  final Db _db;
  final Clock _clock;
  final LogSink _log;

  static const _crewSizes = {'solo', '2-5', '6-10', '11+'};

  Router get router => Router()
    ..get('/', _landing)
    ..get('/sample', _sample)
    ..post('/waitlist', _waitlist)
    ..get('/robots.txt', _robots)
    ..get('/q/<id>', _quote)
    ..post('/q/<id>/approve', _approve)
    ..post('/q/<id>/decline', _decline)
    ..post('/q/<id>/deposit', _deposit)
    ..get(
      '/billing/done',
      (Request r) => _message(
        'You\'re all set',
        'Your plan is active. Go back to the Jobwalk app to keep quoting.',
      ),
    )
    ..get(
      '/billing/cancelled',
      (Request r) => _message(
        'No changes made',
        'You can choose a plan any time from Settings in the Jobwalk app.',
      ),
    )
    ..get(
      '/payments/done',
      (Request r) => _message(
        'Payments are set up',
        'Stripe may take a few minutes to verify your details. Go back to '
            'the Jobwalk app; customers can pay deposits by card as soon '
            'as it\'s ready.',
      ),
    )
    ..get('/payments/refresh', _refreshOnboarding)
    ..post('/webhooks/stripe', _stripeWebhook)
    ..get('/healthz', _health)
    ..get('/readyz', _ready)
    ..get('/metrics', _metrics);

  Future<void> _limit(Request r) async {
    final wait = await perIp.acquire(
      'ip:${clientIp(r, trustedProxies: trustedProxies)}',
    );
    if (wait != null) throw ApiError.rateLimited(wait);
  }

  Response _message(String title, String text) =>
      htmlResponse(200, messagePage(title, text, homeHref: '/'));

  // ---------------------------------------------------------------------------
  // Marketing
  // ---------------------------------------------------------------------------

  Response _landing(Request r) => htmlResponse(
    200,
    landingPage(joined: r.url.queryParameters['joined'] == '1'),
    headers: {'cache-control': 'public, max-age=300'},
  );

  Response _sample(Request r) {
    final now = _clock();
    const profile = BusinessProfile(
      name: 'Brightline Painting',
      trades: [Trade.painting],
      phone: '(512) 555-0142',
      email: 'hello@brightline.example',
    );
    final quote = QuoteBuilder.fromDraft(
      SampleJob.livingRoom.draft,
      id: 'sample',
      number: 1042,
      rates: Rates.forTrade(Trade.painting),
      now: now,
      customer: const Customer(name: 'Dana Ortiz'),
    );
    final view = CustomerView(
      publicId: 'sample',
      businessId: '',
      quoteId: 'sample',
      revision: 1,
      quote: PublicQuote.fromQuote(quote, profile, issuedAt: now),
      response: const CustomerResponse(),
    );
    return htmlResponse(
      200,
      quotePage(view, now: now, homeHref: '/', sample: true),
    );
  }

  Future<Response> _waitlist(Request r) async {
    await _limit(r);
    final isForm = !(r.mimeType ?? '').contains('json');
    final Map<String, Object?> data = isForm
        ? await readForm(r)
        : await readJson(r, maxBytes: 16 * 1024);
    final email = normalizeEmail(data['email']);
    if (email == null) {
      if (isForm) {
        return htmlResponse(
          400,
          landingPage(error: 'Enter a valid email address.'),
        );
      }
      throw ApiError.badRequest(
        'invalid_email',
        'Enter a valid email address.',
      );
    }
    final trade = Trade.values.any((t) => t.id == data['trade'])
        ? data['trade']! as String
        : '';
    final crew = _crewSizes.contains(data['crew'])
        ? data['crew']! as String
        : '';
    await _db.execute(
      '''
      INSERT INTO waitlist (email, trade, crew, created_at)
      VALUES (@e, @t, @c, @now:timestamptz)
      ON CONFLICT (email) DO UPDATE SET trade = EXCLUDED.trade,
        crew = EXCLUDED.crew''',
      {'e': email, 't': trade, 'c': crew, 'now': _clock()},
    );
    _log({'event': 'waitlist', 'trade': trade, 'crew': crew});
    return isForm
        ? seeOther('/?joined=1#join')
        : jsonResponse(200, {'ok': true});
  }

  Response _robots(Request r) => Response.ok(
    'User-agent: *\nDisallow: /q/\nDisallow: /v1/\n',
    headers: {'content-type': 'text/plain; charset=utf-8'},
  );

  // ---------------------------------------------------------------------------
  // The customer's quote
  // ---------------------------------------------------------------------------

  Future<Response> _quote(Request r, String id) async {
    final params = r.url.queryParameters;
    var countView =
        params['preview'] != '1' &&
        params['done'] == null &&
        !_looksLikeBot(r.headers['user-agent'] ?? '');
    if (countView && QuoteService.publicIdPattern.hasMatch(id)) {
      final ip = clientIp(r, trustedProxies: trustedProxies);
      countView = await viewsPerVisitor.acquire('view:$id:$ip') == null;
    }
    final view = await quotes.open(id, countView: countView);
    if (view == null) throw ApiError.notFound();
    return htmlResponse(
      200,
      quotePage(
        view,
        now: _clock(),
        homeHref: '/',
        flash: params['done'],
        error: switch (params['error']) {
          'name' => 'Type your name to approve the quote.',
          'agree' => 'Check the box to approve the quote.',
          'option' => 'Choose one of the options.',
          _ => null,
        },
      ),
      headers: {'x-robots-tag': 'noindex, nofollow'},
    );
  }

  /// Link previews in messaging apps fetch the page; they aren't views.
  static bool _looksLikeBot(String userAgent) => RegExp(
    r'bot|crawl|spider|preview|facebookexternalhit|whatsapp|telegram|slack|'
    r'discord|skype|embedly|curl|wget|python-requests|headless',
    caseSensitive: false,
  ).hasMatch(userAgent);

  Future<Response> _approve(Request r, String id) async {
    await _limit(r);
    final form = await readForm(r);
    final outcome = await quotes.approve(
      id,
      optionId: form['option'] ?? '',
      name: form['name'] ?? '',
      agreed: form['agree'] == 'yes',
      ip: clientIp(r, trustedProxies: trustedProxies),
      userAgent: r.headers['user-agent'] ?? '',
    );
    return switch (outcome) {
      ApproveOutcome.missing => throw ApiError.notFound(),
      ApproveOutcome.approved ||
      ApproveOutcome.alreadyApproved ||
      ApproveOutcome.expired => seeOther('/q/$id?preview=1'),
      ApproveOutcome.option => seeOther(
        '/q/$id?preview=1&error=option#approve',
      ),
      ApproveOutcome.name => seeOther('/q/$id?preview=1&error=name#approve'),
      ApproveOutcome.agree => seeOther('/q/$id?preview=1&error=agree#approve'),
    };
  }

  Future<Response> _decline(Request r, String id) async {
    await _limit(r);
    final form = await readForm(r);
    final found = await quotes.decline(
      id,
      reason: form['reason'] ?? '',
      ip: clientIp(r, trustedProxies: trustedProxies),
      userAgent: r.headers['user-agent'] ?? '',
    );
    if (!found) throw ApiError.notFound();
    return seeOther('/q/$id?preview=1&done=declined');
  }

  Future<Response> _deposit(Request r, String id) async {
    await _limit(r);
    return seeOther((await billing.depositCheckout(id)).toString());
  }

  // ---------------------------------------------------------------------------
  // Stripe
  // ---------------------------------------------------------------------------

  Future<Response> _refreshOnboarding(Request r) async {
    final q = r.url.queryParameters;
    final account = q['account'] ?? '';
    if (!billing.validRefresh(account, q['sig'] ?? '')) {
      throw ApiError.notFound();
    }
    return seeOther(await billing.onboardingLink(account));
  }

  Future<Response> _stripeWebhook(Request r) async {
    final payload = utf8.decode(
      await readBytes(r, 1024 * 1024),
      allowMalformed: true,
    );
    return jsonResponse(
      200,
      await billing.webhook(payload, r.headers['stripe-signature']),
    );
  }

  // ---------------------------------------------------------------------------
  // Operations
  // ---------------------------------------------------------------------------

  /// Liveness: the process is serving.
  Response _health(Request r) => jsonResponse(200, {
    'ok': true,
    'version': version,
    'prompt_version': promptVersion,
    'model': model,
  });

  /// Readiness: the database answers and its schema is current.
  Future<Response> _ready(Request r) async {
    var schema = 0;
    var database = false;
    try {
      final row = await _db.one(
        'SELECT COALESCE(max(version), 0) AS v FROM schema_migrations',
      );
      schema = row!['v'] as int;
      database = true;
    } on Object catch (e) {
      _log({'event': 'not_ready', 'error': '$e'});
    }
    final ok = database && schema >= latestSchemaVersion;
    return jsonResponse(ok ? 200 : 503, {
      'ok': ok,
      'database': database,
      'schema': schema,
      'expected_schema': latestSchemaVersion,
    });
  }

  Response _metrics(Request r) {
    final token = metricsToken;
    final allowed = token != null
        ? constantTimeEquals(bearerToken(r) ?? '', token)
        : exposeMetrics;
    if (!allowed) throw ApiError.notFound();
    return Response.ok(
      metrics.render(),
      headers: {'content-type': 'text/plain; version=0.0.4; charset=utf-8'},
    );
  }
}
