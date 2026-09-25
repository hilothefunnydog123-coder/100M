import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:jobwalk_server/jobwalk_server.dart';

/// Reads configuration, connects to Postgres (waiting for it to come up),
/// migrates, and builds the app with real integrations.
class Setup {
  Setup._(this.config, this.app);

  final ServerConfig config;
  final JobwalkApp app;

  static Future<Setup> load({bool migrateNow = true}) async {
    final ServerConfig config;
    try {
      config = ServerConfig.fromEnvironment(Platform.environment);
    } on ConfigError catch (e) {
      stderr.writeln(e);
      exit(78); // EX_CONFIG
    }
    for (final warning in config.warnings) {
      stdoutLog({'event': 'config_warning', 'message': warning});
    }

    final db = Db.open(
      config.databaseUrl,
      maxConnections: config.databasePoolSize,
    );
    await _waitFor(db);
    if (migrateNow && config.migrateOnStart) {
      final applied = await migrate(db);
      if (applied.isNotEmpty) {
        stdoutLog({'event': 'migrated', 'versions': applied});
      }
    }

    final client = http.Client();
    final QuoteDrafter drafter = config.fakeModel
        ? DemoDrafter()
        : Drafter(
            api: ClaudeClient(
              apiKey: config.anthropicApiKey!,
              baseUrl: config.anthropicBaseUrl,
            ),
            config: config.drafter,
          );
    final EmailSender email = config.emailProvider == 'resend'
        ? ResendEmailSender(
            apiKey: config.resendApiKey!,
            from: config.emailFrom,
            replyTo: config.emailReplyTo,
            client: client,
          )
        : LogEmailSender();
    final ObjectStore store = config.storage == 's3'
        ? S3ObjectStore(
            endpoint: config.s3Endpoint!,
            bucket: config.s3Bucket!,
            region: config.s3Region,
            accessKey: config.s3AccessKeyId!,
            secretKey: config.s3SecretAccessKey!,
            client: client,
          )
        : FileObjectStore(Directory(config.storageDir));
    final stripe = config.stripeSecretKey == null
        ? null
        : StripeClient(secretKey: config.stripeSecretKey!, client: client);

    return Setup._(
      config,
      JobwalkApp(
        config: config,
        db: db,
        drafter: drafter,
        email: email,
        store: store,
        stripe: stripe,
      ),
    );
  }

  /// Containers start in any order; give Postgres half a minute.
  static Future<void> _waitFor(Db db) async {
    for (var i = 0; i < 30; i++) {
      if (await db.ping()) return;
      if (i == 0) stdoutLog({'event': 'waiting_for_database'});
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    stderr.writeln('Could not connect to the database.');
    exit(69); // EX_UNAVAILABLE
  }
}
