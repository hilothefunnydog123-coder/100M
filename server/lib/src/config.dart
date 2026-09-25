import 'drafter.dart';

/// Thrown at startup with every configuration problem found, not just the
/// first.
class ConfigError implements Exception {
  ConfigError(this.problems);

  final List<String> problems;

  @override
  String toString() =>
      'Invalid configuration:\n${problems.map((p) => '  - $p').join('\n')}';
}

/// Everything the server reads from its environment. See `.env.example`
/// and docs/DEPLOY.md for what each setting does.
///
/// Jobwalk's own settings are namespaced `JOBWALK_*` on purpose: generic
/// names such as `CLAUDE_EFFORT` are set by other tools and would silently
/// change cost and latency here.
class ServerConfig {
  const ServerConfig({
    required this.env,
    required this.databaseUrl,
    required this.publicUrl,
    required this.secret,
    required this.drafter,
    this.port = 8080,
    this.databasePoolSize = 10,
    this.migrateOnStart = true,
    this.runWorker = true,
    this.corsOrigins = const ['*'],
    this.trustedProxies = 1,
    this.anthropicApiKey,
    this.anthropicBaseUrl,
    this.fakeModel = false,
    this.maxConcurrentDrafts = 16,
    this.maxQueuedDrafts = 64,
    this.draftTimeout = const Duration(seconds: 170),
    this.emailProvider = 'log',
    this.resendApiKey,
    this.emailFrom = 'Jobwalk <hello@jobwalk.app>',
    this.emailReplyTo,
    this.storage = 'file',
    this.storageDir = 'data/objects',
    this.s3Endpoint,
    this.s3Bucket,
    this.s3Region = 'auto',
    this.s3AccessKeyId,
    this.s3SecretAccessKey,
    this.stripeSecretKey,
    this.stripeWebhookSecrets = const [],
    this.stripePricePro,
    this.stripePriceCrew,
    this.platformFeeBps = 100,
    this.processingFeeBps = 290,
    this.processingFeeCents = 30,
    this.adminToken,
    this.metricsToken,
    this.trialDrafts = 25,
    this.monthlyDraftCap = 500,
    this.sessionDays = 90,
    this.reviewEmail,
    this.reviewCode,
    this.warnings = const [],
  });

  /// `development`, `test`, or `production`.
  final String env;
  bool get isProduction => env == 'production';

  final int port;
  final String databaseUrl;
  final int databasePoolSize;

  /// Apply pending migrations at startup. Turn off to run `bin/migrate.dart`
  /// as a separate release step instead.
  final bool migrateOnStart;

  /// Run background jobs in this process. Turn off on web-only instances
  /// when a separate worker runs `bin/worker.dart`.
  final bool runWorker;

  /// Origin for links in emails and on quotes, e.g. `https://jobwalk.app`.
  final Uri publicUrl;

  /// Signs sign-in codes and onboarding links. At least 32 characters.
  final String secret;
  final List<String> corsOrigins;

  /// Load balancers between the internet and this server (for client IPs).
  final int trustedProxies;

  final String? anthropicApiKey;

  /// Honors `ANTHROPIC_BASE_URL`, like the official SDKs.
  final Uri? anthropicBaseUrl;

  /// Canned sample drafts instead of Claude (development only).
  final bool fakeModel;
  final DrafterConfig drafter;
  final int maxConcurrentDrafts;
  final int maxQueuedDrafts;
  final Duration draftTimeout;

  /// `log` (prints emails; development) or `resend`.
  final String emailProvider;
  final String? resendApiKey;
  final String emailFrom;
  final String? emailReplyTo;

  /// `file` (a directory; one instance) or `s3` (S3, R2, MinIO...).
  final String storage;
  final String storageDir;
  final Uri? s3Endpoint;
  final String? s3Bucket;
  final String s3Region;
  final String? s3AccessKeyId;
  final String? s3SecretAccessKey;

  /// Billing and deposits are off unless a Stripe key is set.
  final String? stripeSecretKey;
  final List<String> stripeWebhookSecrets;
  final String? stripePricePro;
  final String? stripePriceCrew;
  final int platformFeeBps;
  final int processingFeeBps;
  final int processingFeeCents;

  final String? adminToken;
  final String? metricsToken;

  final int trialDrafts;
  final int monthlyDraftCap;
  final int sessionDays;
  final String? reviewEmail;
  final String? reviewCode;

  /// Settings that work but deserve a look, printed at startup.
  final List<String> warnings;

  bool get stripeEnabled => stripeSecretKey != null;

  static const _devSecret = 'development-secret-do-not-use-in-production';

  factory ServerConfig.fromEnvironment(Map<String, String> env) {
    final problems = <String>[];
    final warnings = <String>[];
    String? str(String name) {
      final v = env[name]?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    int intVar(String name, int fallback, {int min = 0, int? max}) {
      final raw = str(name);
      if (raw == null) return fallback;
      final v = int.tryParse(raw);
      if (v == null || v < min || (max != null && v > max)) {
        problems.add(
          '$name must be a whole number'
          '${max == null ? ' of at least $min' : ' from $min to $max'}.',
        );
        return fallback;
      }
      return v;
    }

    bool boolVar(String name, bool fallback) {
      final raw = str(name)?.toLowerCase();
      return switch (raw) {
        null => fallback,
        'true' || '1' || 'yes' => true,
        'false' || '0' || 'no' => false,
        _ => () {
          problems.add('$name must be true or false.');
          return fallback;
        }(),
      };
    }

    Uri? urlVar(String name) {
      final raw = str(name);
      if (raw == null) return null;
      final uri = Uri.tryParse(raw);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        problems.add('$name must be an absolute URL.');
        return null;
      }
      return uri;
    }

    final mode = str('JOBWALK_ENV') ?? 'development';
    if (!const {'development', 'test', 'production'}.contains(mode)) {
      problems.add('JOBWALK_ENV must be development, test, or production.');
    }
    final production = mode == 'production';

    final databaseUrl =
        str('DATABASE_URL') ??
        (production
            ? null
            : 'postgres://postgres:postgres@localhost:5432/jobwalk');
    if (databaseUrl == null) problems.add('DATABASE_URL is required.');

    var publicUrl = urlVar('JOBWALK_PUBLIC_URL');
    if (publicUrl == null) {
      if (production) problems.add('JOBWALK_PUBLIC_URL is required.');
      publicUrl = Uri.parse('http://localhost:${intVar('PORT', 8080)}');
    } else if (production && publicUrl.scheme != 'https') {
      problems.add('JOBWALK_PUBLIC_URL must use https in production.');
    }

    var secret = str('JOBWALK_SECRET');
    if (secret == null) {
      if (production) problems.add('JOBWALK_SECRET is required.');
      secret = _devSecret;
    } else if (secret.length < 32) {
      problems.add('JOBWALK_SECRET must be at least 32 characters.');
    }

    final fake = boolVar('JOBWALK_FAKE_MODEL', false);
    final apiKey = str('ANTHROPIC_API_KEY');
    if (fake && production) {
      problems.add('JOBWALK_FAKE_MODEL is for development only.');
    } else if (!fake && apiKey == null) {
      problems.add(
        'ANTHROPIC_API_KEY is not set. Set it, or set JOBWALK_FAKE_MODEL=true '
        'for canned sample drafts.',
      );
    }
    const efforts = {'low', 'medium', 'high', 'xhigh', 'max'};
    final effort = str('JOBWALK_EFFORT') ?? 'high';
    if (!efforts.contains(effort)) {
      problems.add('JOBWALK_EFFORT must be one of ${efforts.join(', ')}.');
    }

    final emailProvider = str('EMAIL_PROVIDER') ?? 'log';
    final resendKey = str('RESEND_API_KEY');
    if (emailProvider == 'resend') {
      if (resendKey == null) problems.add('RESEND_API_KEY is required.');
    } else if (emailProvider == 'log') {
      if (production) {
        problems.add(
          'EMAIL_PROVIDER=log prints sign-in codes to the log. Use resend in '
          'production.',
        );
      }
    } else {
      problems.add('EMAIL_PROVIDER must be log or resend.');
    }

    final storage = str('STORAGE') ?? 'file';
    final s3Endpoint = urlVar('S3_ENDPOINT');
    if (storage == 's3') {
      for (final name in [
        'S3_ENDPOINT',
        'S3_BUCKET',
        'S3_ACCESS_KEY_ID',
        'S3_SECRET_ACCESS_KEY',
      ]) {
        if (str(name) == null) {
          problems.add('$name is required for STORAGE=s3.');
        }
      }
    } else if (storage == 'file') {
      if (production) {
        warnings.add(
          'STORAGE=file keeps photos on this machine. Use a persistent volume '
          'and one instance, or STORAGE=s3.',
        );
      }
    } else {
      problems.add('STORAGE must be file or s3.');
    }

    final stripeKey = str('STRIPE_SECRET_KEY');
    final webhookSecrets = [
      ?str('STRIPE_WEBHOOK_SECRET'),
      ?str('STRIPE_CONNECT_WEBHOOK_SECRET'),
    ];
    if (stripeKey != null) {
      if (webhookSecrets.isEmpty) {
        problems.add(
          'STRIPE_WEBHOOK_SECRET is required with STRIPE_SECRET_KEY.',
        );
      }
      if (production && stripeKey.startsWith('sk_test_')) {
        warnings.add('STRIPE_SECRET_KEY is a test key.');
      }
      if (str('STRIPE_PRICE_PRO') == null) {
        warnings.add(
          'STRIPE_PRICE_PRO is not set; the Pro plan can\'t be bought.',
        );
      }
    } else if (production) {
      warnings.add(
        'STRIPE_SECRET_KEY is not set: billing and deposits are off.',
      );
    }

    final reviewEmail = str('JOBWALK_REVIEW_EMAIL');
    final reviewCode = str('JOBWALK_REVIEW_CODE');
    if ((reviewEmail == null) != (reviewCode == null)) {
      problems.add(
        'Set both JOBWALK_REVIEW_EMAIL and JOBWALK_REVIEW_CODE, or '
        'neither.',
      );
    } else if (reviewCode != null && !RegExp(r'^\d{6}$').hasMatch(reviewCode)) {
      problems.add('JOBWALK_REVIEW_CODE must be six digits.');
    }

    final adminToken = str('ADMIN_TOKEN');
    if (adminToken != null && adminToken.length < 24) {
      problems.add('ADMIN_TOKEN must be at least 24 characters.');
    }

    final config = ServerConfig(
      env: mode,
      port: intVar('PORT', 8080, min: 1, max: 65535),
      databaseUrl: databaseUrl ?? '',
      databasePoolSize: intVar('DATABASE_POOL_SIZE', 10, min: 1, max: 200),
      migrateOnStart: boolVar('JOBWALK_MIGRATE_ON_START', true),
      runWorker: boolVar('JOBWALK_RUN_WORKER', true),
      publicUrl: publicUrl.replace(path: '', query: null, fragment: null),
      secret: secret,
      corsOrigins: (str('JOBWALK_CORS_ORIGINS') ?? '*')
          .split(',')
          .map((o) => o.trim())
          .where((o) => o.isNotEmpty)
          .toList(),
      trustedProxies: intVar('JOBWALK_TRUSTED_PROXIES', 1, max: 5),
      anthropicApiKey: apiKey,
      anthropicBaseUrl: urlVar('ANTHROPIC_BASE_URL'),
      fakeModel: fake,
      drafter: DrafterConfig(
        model: str('JOBWALK_MODEL') ?? 'claude-opus-5-5',
        effort: effort,
        maxTokens: intVar('JOBWALK_MAX_TOKENS', 32000, min: 1000),
        useFallbacks: boolVar('JOBWALK_FALLBACKS', true),
      ),
      maxConcurrentDrafts: intVar('JOBWALK_MAX_CONCURRENT', 16, min: 1),
      maxQueuedDrafts: intVar('JOBWALK_MAX_QUEUED', 64),
      draftTimeout: Duration(
        seconds: intVar('JOBWALK_DRAFT_TIMEOUT_SECONDS', 170, min: 10),
      ),
      emailProvider: emailProvider,
      resendApiKey: resendKey,
      emailFrom: str('EMAIL_FROM') ?? 'Jobwalk <hello@jobwalk.app>',
      emailReplyTo: str('EMAIL_REPLY_TO'),
      storage: storage,
      storageDir: str('STORAGE_DIR') ?? 'data/objects',
      s3Endpoint: s3Endpoint,
      s3Bucket: str('S3_BUCKET'),
      s3Region: str('S3_REGION') ?? 'auto',
      s3AccessKeyId: str('S3_ACCESS_KEY_ID'),
      s3SecretAccessKey: str('S3_SECRET_ACCESS_KEY'),
      stripeSecretKey: stripeKey,
      stripeWebhookSecrets: webhookSecrets,
      stripePricePro: str('STRIPE_PRICE_PRO'),
      stripePriceCrew: str('STRIPE_PRICE_CREW'),
      platformFeeBps: intVar('STRIPE_APPLICATION_FEE_BPS', 100, max: 2000),
      processingFeeBps: intVar('STRIPE_PROCESSING_FEE_BPS', 290, max: 1000),
      processingFeeCents: intVar('STRIPE_PROCESSING_FEE_CENTS', 30, max: 500),
      adminToken: adminToken,
      metricsToken: str('METRICS_TOKEN'),
      trialDrafts: intVar('JOBWALK_TRIAL_DRAFTS', 25),
      monthlyDraftCap: intVar('JOBWALK_MONTHLY_DRAFT_CAP', 500, min: 1),
      sessionDays: intVar('JOBWALK_SESSION_DAYS', 90, min: 1, max: 400),
      reviewEmail: reviewEmail?.toLowerCase(),
      reviewCode: reviewCode,
      warnings: warnings,
    );
    if (problems.isNotEmpty) throw ConfigError(problems);
    return config;
  }
}
