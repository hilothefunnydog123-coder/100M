import 'drafter.dart';
import 'gemini_drafter.dart';
import 'groq_drafter.dart';

/// Thrown at startup with every configuration problem found, not just the
/// first.
class ConfigError implements Exception {
  ConfigError(this.problems);

  final List<String> problems;

  @override
  String toString() =>
      'Invalid configuration:\n${problems.map((p) => '  - $p').join('\n')}';
}

/// A model to draft with, and which provider runs it.
typedef ModelRef = ({String provider, String model});

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
    this.aiProvider = 'claude',
    this.anthropicApiKey,
    this.anthropicBaseUrl,
    this.groqApiKey,
    this.groqBaseUrl,
    this.groqDrafter = const GroqDrafterConfig(),
    this.geminiApiKey,
    this.geminiBaseUrl,
    this.geminiDrafter = const GeminiDrafterConfig(),
    this.fakeModel = false,
    this.freeTier = false,
    this.backupModels = const [],
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
    this.proPriceCents = 3500,
    this.crewPriceCents = 7900,
    this.sessionDays = 90,
    this.reviewEmail,
    this.reviewCode,
    this.legalName = 'Jobwalk',
    this.contactEmail = 'hello@jobwalk.app',
    this.legalAddress = '',
    this.governingLaw = '',
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

  /// `claude` (default), `groq` (an open-weights model on Groq), or
  /// `gemini`.
  final String aiProvider;

  final String? anthropicApiKey;

  /// Honors `ANTHROPIC_BASE_URL`, like the official SDKs.
  final Uri? anthropicBaseUrl;

  final String? groqApiKey;

  /// Honors `GROQ_BASE_URL`, like Groq's SDKs.
  final Uri? groqBaseUrl;

  /// `GEMINI_API_KEY`, or `GOOGLE_API_KEY` like Google's SDKs.
  final String? geminiApiKey;
  final Uri? geminiBaseUrl;

  /// Canned sample drafts instead of a model (development only).
  final bool fakeModel;

  /// Drafting on free AI plans (`JOBWALK_FREE_TIER`): Groq's free-tier
  /// limits apply, Gemini's free models back each other up, and the privacy
  /// policy says Google may use what its free tier is sent.
  final bool freeTier;

  /// Tried in order when the main model's provider turns a draft away
  /// (busy, rate limited, out of quota). `JOBWALK_BACKUP_MODELS`.
  final List<ModelRef> backupModels;

  /// Backups used when `JOBWALK_BACKUP_MODELS` isn't set: an older model
  /// from the same provider, so the key, billing, and terms stay the same.
  static const defaultBackups = {
    'claude': 'claude-sonnet-5',
    'gemini': 'gemini-3.7-flash',
  };

  /// Gemini backups on the free tier, each with its own daily allowance:
  /// another Flash model, then Flash-Lite (hundreds a day). Groq's free
  /// model follows when there's a key for it, since Google's models tend
  /// to be busy at the same time.
  static const freeTierBackups = ['gemini-3.7-flash', 'gemini-3.5-flash-lite'];

  /// Settings for the provider in use; the others keep their defaults.
  final DrafterConfig drafter;
  final GroqDrafterConfig groqDrafter;
  final GeminiDrafterConfig geminiDrafter;

  /// The model drafts use, for logs and the health endpoint.
  String get draftModel => fakeModel
      ? 'demo'
      : switch (aiProvider) {
          'groq' => groqDrafter.model,
          'gemini' => geminiDrafter.model,
          _ => drafter.model,
        };

  String get draftEffort => switch (aiProvider) {
    'groq' => groqDrafter.effort,
    'gemini' => geminiDrafter.effort,
    _ => drafter.effort,
  };

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

  /// Monthly plan prices as shown on the landing page and in the app. Stripe
  /// charges whatever `STRIPE_PRICE_PRO` and `STRIPE_PRICE_CREW` say, so
  /// keep them the same.
  final int proPriceCents;
  final int crewPriceCents;
  final int sessionDays;
  final String? reviewEmail;
  final String? reviewCode;

  /// Who runs this server, for the privacy policy and terms at /privacy
  /// and /terms: the company's legal name, where to reach it, its mailing
  /// address, and the state whose laws govern the terms.
  final String legalName;
  final String contactEmail;
  final String legalAddress;
  final String governingLaw;

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
    final databasePoolSize = intVar('DATABASE_POOL_SIZE', 10, min: 1, max: 200);
    if (databaseUrl != null && databaseUrl.contains('[YOUR-PASSWORD]')) {
      problems.add(
        'DATABASE_URL still says [YOUR-PASSWORD]. Put your database password '
        'there.',
      );
    }
    final databaseHost = Uri.tryParse(databaseUrl ?? '');
    if (databaseHost != null && _isSupabase(databaseHost.host)) {
      // Migrations hold a session lock, which a transaction pooler would
      // hand to other clients mid-migration.
      if (databaseHost.port == 6543) {
        problems.add(
          "DATABASE_URL uses Supabase's transaction pooler (port 6543). Use "
          'the session pooler (port 5432) or the direct connection.',
        );
      } else if (databaseHost.host.toLowerCase().endsWith(
            '.pooler.supabase.com',
          ) &&
          databasePoolSize > 7) {
        warnings.add(
          "Supabase's session pooler allows 15 connections in all unless you "
          'raise its Pool Size (Database settings), and each server opens up '
          'to DATABASE_POOL_SIZE ($databasePoolSize). With two servers, set '
          'it to 5.',
        );
      }
    }

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

    final provider = str('JOBWALK_AI_PROVIDER') ?? 'claude';
    if (!const {'claude', 'groq', 'gemini'}.contains(provider)) {
      problems.add('JOBWALK_AI_PROVIDER must be claude, groq, or gemini.');
    }
    final groq = provider == 'groq';
    final gemini = provider == 'gemini';
    final fake = boolVar('JOBWALK_FAKE_MODEL', false);
    final apiKey = str('ANTHROPIC_API_KEY');
    final groqKey = str('GROQ_API_KEY');
    final geminiKey = str('GEMINI_API_KEY') ?? str('GOOGLE_API_KEY');
    final (keyName, key) = switch (provider) {
      'groq' => ('GROQ_API_KEY', groqKey),
      'gemini' => ('GEMINI_API_KEY', geminiKey),
      _ => ('ANTHROPIC_API_KEY', apiKey),
    };
    if (fake && production) {
      problems.add('JOBWALK_FAKE_MODEL is for development only.');
    } else if (!fake && key == null) {
      problems.add(
        '$keyName is not set. Set it, or set JOBWALK_FAKE_MODEL=true for '
        'canned sample drafts.',
      );
    }
    // Free AI plans have daily limits and busy spells, and Google may use
    // what its free tier is sent. Fine for a beta, not for paying customers.
    final freeTier = boolVar('JOBWALK_FREE_TIER', false);
    final groqFreeTier = freeTier || boolVar('JOBWALK_GROQ_FREE_TIER', false);

    // Backups: "provider:model", or a model whose name says its provider.
    final backupModels = <ModelRef>[];
    if (!fake) {
      final keys = {'claude': apiKey, 'gemini': geminiKey, 'groq': groqKey};
      final mainModel =
          str('JOBWALK_MODEL') ??
          switch (provider) {
            'groq' => const GroqDrafterConfig().model,
            'gemini' => GeminiDrafterConfig.defaultModel,
            _ => const DrafterConfig().model,
          };
      final setting = str('JOBWALK_BACKUP_MODELS');
      final entries = switch (setting?.toLowerCase()) {
        null when freeTier && provider == 'gemini' => [
          ...freeTierBackups,
          if (groqKey != null) 'groq:${GroqDrafterConfig.defaultModel}',
        ],
        null => [?defaultBackups[provider]],
        'none' || 'off' => const <String>[],
        _ => setting!.split(','),
      };
      for (final raw in entries) {
        final entry = raw.trim();
        if (entry.isEmpty) continue;
        final colon = entry.indexOf(':');
        final model = entry.substring(colon + 1).trim();
        final runBy = colon > 0
            ? entry.substring(0, colon).trim()
            : model.startsWith('claude-')
            ? 'claude'
            : model.startsWith('gemini-')
            ? 'gemini'
            : '';
        if (!keys.containsKey(runBy) || model.isEmpty) {
          problems.add(
            'JOBWALK_BACKUP_MODELS: say which provider runs "$entry", such '
            'as groq:$model.',
          );
          continue;
        }
        final ref = (provider: runBy, model: model);
        if ((runBy == provider && model == mainModel) ||
            backupModels.contains(ref)) {
          continue;
        }
        if (keys[runBy] == null) {
          final keyName = switch (runBy) {
            'groq' => 'GROQ_API_KEY',
            'gemini' => 'GEMINI_API_KEY',
            _ => 'ANTHROPIC_API_KEY',
          };
          problems.add(
            'JOBWALK_BACKUP_MODELS uses $model, which needs $keyName.',
          );
          continue;
        }
        backupModels.add(ref);
      }
    }
    final groqPreset = groqFreeTier
        ? GroqDrafterConfig.freeTier
        : const GroqDrafterConfig();
    if (freeTier && production) {
      warnings.add(
        'JOBWALK_FREE_TIER: drafts use free AI plans, with daily limits and '
        'busy spells, and Google may use what it is sent to improve its '
        'products. Fine for a beta; move to paid plans for paying customers.',
      );
    } else if (groq && groqFreeTier && production) {
      warnings.add(
        "JOBWALK_GROQ_FREE_TIER sends one photo per draft, and Groq's free "
        'tier allows roughly 25 to 30 drafts a day across all users.',
      );
    }
    final efforts = switch (provider) {
      'groq' => GroqDrafterConfig.efforts,
      'gemini' => GeminiDrafterConfig.efforts,
      _ => DrafterConfig.efforts,
    };
    final effort =
        str('JOBWALK_EFFORT') ??
        switch (provider) {
          'groq' => groqPreset.effort,
          'gemini' => const GeminiDrafterConfig().effort,
          _ => 'high',
        };
    if (!efforts.contains(effort)) {
      final using = switch (provider) {
        'groq' => ' with Groq',
        'gemini' => ' with Gemini',
        _ => '',
      };
      problems.add(
        'JOBWALK_EFFORT must be one of ${efforts.join(', ')}$using.',
      );
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
      if (s3Endpoint != null && _isSupabase(s3Endpoint.host)) {
        if (!s3Endpoint.path
            .replaceAll(RegExp(r'/+$'), '')
            .endsWith('/storage/v1/s3')) {
          problems.add(
            'S3_ENDPOINT for Supabase ends in /storage/v1/s3. Copy it from '
            'Storage, S3 settings.',
          );
        }
        if ((str('S3_REGION') ?? 'auto') == 'auto') {
          problems.add(
            "S3_REGION must be your Supabase project's region, such as "
            'us-east-1. Copy it from Storage, S3 settings.',
          );
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

    final legalName = str('JOBWALK_LEGAL_NAME');
    final governingLaw = str('JOBWALK_GOVERNING_LAW');
    if (production && (legalName == null || governingLaw == null)) {
      warnings.add(
        'Set JOBWALK_LEGAL_NAME and JOBWALK_GOVERNING_LAW: the privacy '
        'policy and terms name the company and the governing law.',
      );
    }
    final contactEmail =
        str('JOBWALK_CONTACT_EMAIL') ??
        str('EMAIL_REPLY_TO') ??
        RegExp(r'[^<\s]+@[^>\s]+').firstMatch(str('EMAIL_FROM') ?? '')?[0] ??
        'hello@jobwalk.app';

    final adminToken = str('ADMIN_TOKEN');
    if (adminToken != null && adminToken.length < 24) {
      problems.add('ADMIN_TOKEN must be at least 24 characters.');
    }

    final config = ServerConfig(
      env: mode,
      port: intVar('PORT', 8080, min: 1, max: 65535),
      databaseUrl: databaseUrl ?? '',
      databasePoolSize: databasePoolSize,
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
      aiProvider: provider,
      anthropicApiKey: apiKey,
      anthropicBaseUrl: urlVar('ANTHROPIC_BASE_URL'),
      groqApiKey: groqKey,
      groqBaseUrl: urlVar('GROQ_BASE_URL'),
      fakeModel: fake,
      freeTier: freeTier,
      backupModels: backupModels,
      drafter: groq || gemini
          ? const DrafterConfig()
          : DrafterConfig(
              model: str('JOBWALK_MODEL') ?? 'claude-opus-5-5',
              effort: effort,
              maxTokens: intVar('JOBWALK_MAX_TOKENS', 32000, min: 1000),
              useFallbacks: boolVar('JOBWALK_FALLBACKS', true),
            ),
      groqDrafter: groq
          ? groqPreset.copyWith(
              model: str('JOBWALK_MODEL'),
              effort: effort,
              maxTokens: intVar(
                'JOBWALK_MAX_TOKENS',
                groqPreset.maxTokens,
                min: 1000,
              ),
            )
          : groqPreset,
      geminiApiKey: geminiKey,
      geminiBaseUrl: urlVar('GEMINI_BASE_URL'),
      geminiDrafter: gemini
          ? GeminiDrafterConfig(
              model: str('JOBWALK_MODEL') ?? GeminiDrafterConfig.defaultModel,
              effort: effort,
              maxTokens: intVar('JOBWALK_MAX_TOKENS', 32000, min: 1000),
            )
          : const GeminiDrafterConfig(),
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
      proPriceCents: intVar('JOBWALK_PRO_PRICE', 35, min: 1, max: 10000) * 100,
      crewPriceCents:
          intVar('JOBWALK_CREW_PRICE', 79, min: 1, max: 10000) * 100,
      sessionDays: intVar('JOBWALK_SESSION_DAYS', 90, min: 1, max: 400),
      reviewEmail: reviewEmail?.toLowerCase(),
      reviewCode: reviewCode,
      legalName: legalName ?? 'Jobwalk',
      contactEmail: contactEmail,
      legalAddress: str('JOBWALK_LEGAL_ADDRESS') ?? '',
      governingLaw: governingLaw ?? '',
      warnings: warnings,
    );
    if (problems.isNotEmpty) throw ConfigError(problems);
    return config;
  }
}

bool _isSupabase(String host) {
  final h = host.toLowerCase();
  return h.endsWith('.supabase.co') || h.endsWith('.supabase.com');
}
