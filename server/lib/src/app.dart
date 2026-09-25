import 'package:shelf/shelf.dart';

import 'background.dart';
import 'common.dart';
import 'config.dart';
import 'db/database.dart';
import 'db/pg_limiter.dart';
import 'drafter.dart';
import 'http/admin_routes.dart';
import 'http/api_routes.dart';
import 'http/middleware.dart';
import 'http/public_routes.dart';
import 'integrations/email.dart';
import 'integrations/object_store.dart';
import 'integrations/stripe.dart';
import 'jobs.dart';
import 'limits.dart';
import 'metrics.dart';
import 'services/accounts.dart';
import 'services/billing.dart';
import 'services/drafts.dart';
import 'services/maintenance.dart';
import 'services/outbox.dart';
import 'services/photos.dart';
import 'services/plans.dart';
import 'services/quotes.dart';

/// Build version, set with `--define=JOBWALK_VERSION=<git sha>`.
const serverVersion = String.fromEnvironment(
  'JOBWALK_VERSION',
  defaultValue: 'dev',
);

/// Rate limits as (burst, time to regain one).
class Limits {
  const Limits({
    this.codePerEmail = const (5, Duration(minutes: 10)),
    this.codePerIp = const (20, Duration(minutes: 3)),
    this.verifyPerIp = const (30, Duration(minutes: 1)),
    this.publicPerIp = const (60, Duration(seconds: 10)),
    this.draftsPerBusiness = const (10, Duration(minutes: 3)),
    this.apiPerUser = const (300, Duration(milliseconds: 200)),
  });

  /// For tests: nothing is limited in practice.
  static const relaxed = Limits(
    codePerEmail: (100000, Duration(milliseconds: 1)),
    codePerIp: (100000, Duration(milliseconds: 1)),
    verifyPerIp: (100000, Duration(milliseconds: 1)),
    publicPerIp: (100000, Duration(milliseconds: 1)),
    draftsPerBusiness: (100000, Duration(milliseconds: 1)),
    apiPerUser: (100000, Duration(milliseconds: 1)),
  );

  final (int, Duration) codePerEmail;
  final (int, Duration) codePerIp;
  final (int, Duration) verifyPerIp;
  final (int, Duration) publicPerIp;
  final (int, Duration) draftsPerBusiness;
  final (int, Duration) apiPerUser;
}

/// The whole server: services wired to the database and integrations,
/// the HTTP handler, and the background worker.
class JobwalkApp {
  JobwalkApp({
    required this.config,
    required this.db,
    required QuoteDrafter drafter,
    required EmailSender email,
    required ObjectStore store,
    StripeClient? stripe,
    Limits limits = const Limits(),
    Clock clock = systemClock,
    LogSink log = stdoutLog,
  }) : _clock = clock,
       _log = log {
    Limiter shared((int, Duration) l) =>
        PgLimiter(db, capacity: l.$1, refillEvery: l.$2, clock: clock);

    final plans = PlanRules(
      trialDrafts: config.trialDrafts,
      monthlyDraftCap: config.monthlyDraftCap,
    );
    outbox = Outbox(
      templates: EmailTemplates(appUrl: config.publicUrl.toString()),
      clock: clock,
      onEnqueue: () => worker.kick(),
    );
    accounts = AccountService(
      db: db,
      outbox: outbox,
      settings: AccountSettings(
        secret: config.secret,
        sessionTtl: Duration(days: config.sessionDays),
        reviewEmail: config.reviewEmail,
        reviewCode: config.reviewCode,
        plans: plans,
      ),
      codePerEmail: shared(limits.codePerEmail),
      codePerIp: shared(limits.codePerIp),
      verifyPerIp: shared(limits.verifyPerIp),
      clock: clock,
      log: log,
    );
    quotes = QuoteService(
      db: db,
      outbox: outbox,
      publicUrl: config.publicUrl,
      onlineDeposits: stripe != null,
      clock: clock,
      log: log,
    );
    photos = PhotoService(db: db, store: store, clock: clock);
    concurrency = ConcurrencyLimiter(
      maxConcurrent: config.maxConcurrentDrafts,
      maxQueued: config.maxQueuedDrafts,
    );
    final draftsTotal = metrics.counter(
      'jobwalk_drafts_total',
      'AI drafts by outcome.',
      labels: ['outcome'],
    );
    final draftCost = metrics.counter(
      'jobwalk_draft_cost_usd_total',
      'Estimated model spend on drafts.',
    );
    final draftSeconds = metrics.histogram(
      'jobwalk_draft_duration_seconds',
      'Time to draft a quote.',
      buckets: const [5, 10, 20, 30, 45, 60, 90, 120, 170],
    );
    drafts = DraftService(
      db: db,
      drafter: drafter,
      concurrency: concurrency,
      perBusiness: shared(limits.draftsPerBusiness),
      plans: plans,
      timeout: config.draftTimeout,
      clock: clock,
      log: log,
      onDraft: (d) {
        draftsTotal.inc([d.outcome]);
        draftCost.inc(const [], d.costUsd);
        draftSeconds.observe(d.ms / 1000);
      },
    );
    billing = BillingService(
      db: db,
      stripe: stripe,
      settings: BillingSettings(
        webhookSecrets: config.stripeWebhookSecrets,
        proPriceId: config.stripePricePro,
        crewPriceId: config.stripePriceCrew,
        platformFeeBps: config.platformFeeBps,
        processingFeeBps: config.processingFeeBps,
        processingFeeCents: config.processingFeeCents,
      ),
      publicUrl: config.publicUrl,
      quotes: quotes,
      linkSecret: config.secret,
      clock: clock,
      log: log,
    );
    maintenance = Maintenance(db: db, outbox: outbox, clock: clock, log: log);
    final jobsTotal = metrics.counter(
      'jobwalk_jobs_total',
      'Background jobs run, by kind and outcome.',
      labels: ['kind', 'outcome'],
    );
    worker = Worker(
      db: db,
      handlers: jobHandlers(
        email: email,
        store: store,
        quotes: quotes,
        billing: billing,
        maintenance: maintenance,
      ),
      clock: clock,
      log: log,
      onJob: (kind, ok) => jobsTotal.inc([kind, ok ? 'ok' : 'error']),
    );
    metrics
      ..gauge(
        'jobwalk_drafts_active',
        'Drafts calling the model now.',
        () => concurrency.active,
      )
      ..gauge(
        'jobwalk_drafts_queued',
        'Drafts waiting for a slot.',
        () => concurrency.queued,
      );

    final api = ApiRoutes(
      accounts: accounts,
      quotes: quotes,
      photos: photos,
      drafts: drafts,
      billing: billing,
      perUser: MemoryLimiter(
        RateLimiter(
          capacity: limits.apiPerUser.$1,
          refillEvery: limits.apiPerUser.$2,
          clock: clock,
        ),
      ),
      trustedProxies: config.trustedProxies,
    );
    final public = PublicRoutes(
      db: db,
      quotes: quotes,
      billing: billing,
      perIp: shared(limits.publicPerIp),
      metrics: metrics,
      model: config.fakeModel ? 'demo' : config.drafter.model,
      version: serverVersion,
      metricsToken: config.metricsToken,
      exposeMetrics: !config.isProduction,
      trustedProxies: config.trustedProxies,
      clock: clock,
      log: log,
    );
    final admin = AdminRoutes(db: db, token: config.adminToken, clock: clock);
    final routes = Cascade()
        .add(api.router.call)
        .add(public.router.call)
        .add(admin.router.call)
        .add((Request r) => throw ApiError.notFound())
        .handler;
    handler = const Pipeline()
        .addMiddleware(requestIds())
        .addMiddleware(accessLog(log, metrics))
        .addMiddleware(securityHeaders(hsts: config.isProduction))
        .addMiddleware(cors(config.corsOrigins))
        .addMiddleware(errors(log))
        .addMiddleware(drain(() => draining))
        .addHandler(routes);
  }

  final ServerConfig config;
  final Db db;
  final metrics = Metrics();
  final Clock _clock;
  final LogSink _log;

  late final Outbox outbox;
  late final AccountService accounts;
  late final QuoteService quotes;
  late final PhotoService photos;
  late final DraftService drafts;
  late final BillingService billing;
  late final Maintenance maintenance;
  late final ConcurrencyLimiter concurrency;
  late final Worker worker;
  late final Handler handler;

  /// Set during shutdown: new requests get 503 so the load balancer moves
  /// on, while in-flight ones finish.
  bool draining = false;

  /// Starts background work (unless this instance is web-only).
  Future<void> start({bool? runWorker}) async {
    await maintenance.schedule();
    if (runWorker ?? config.runWorker) worker.start();
    _log({
      'event': 'started',
      'version': serverVersion,
      'worker': runWorker ?? config.runWorker,
      'at': _clock().toIso8601String(),
    });
  }

  Future<void> stop() => worker.stop();
}
