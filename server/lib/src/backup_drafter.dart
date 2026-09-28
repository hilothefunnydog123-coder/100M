import 'package:jobwalk_core/jobwalk_core.dart';

import 'claude_client.dart';
import 'common.dart';
import 'config.dart';
import 'drafter.dart';
import 'gemini_client.dart';
import 'gemini_drafter.dart';
import 'groq_client.dart';
import 'groq_drafter.dart';
import 'model_api.dart';

/// Drafts with the main model and, when its provider turns the request
/// away, with each backup in turn, so a busy model doesn't leave a
/// contractor in the driveway without a quote.
///
/// Turned away means no model worked on the job: the provider was busy or
/// unreachable (5xx, timeouts, dropped connections), rate limited or out of
/// quota (429), refused the key or the billing (401, 403), or no longer has
/// the model (404). An answer a model did give (a refusal, photos it
/// couldn't use, output that wouldn't parse) stands and isn't sent on.
class BackupDrafter implements QuoteDrafter {
  BackupDrafter(this.models, {LogSink? log}) : _log = log ?? ((_) {}) {
    if (models.length < 2) {
      throw ArgumentError.value(models, 'models', 'Needs at least a backup.');
    }
  }

  /// The main model first, then the backups in the order they're tried.
  final List<({String model, QuoteDrafter drafter})> models;
  final LogSink _log;

  @override
  Future<Draft> draft(DraftRequest request, {String? userId}) async {
    for (var i = 0; ; i++) {
      try {
        return await models[i].drafter.draft(request, userId: userId);
      } on DraftFailed catch (e) {
        if (i + 1 == models.length || !turnedAway(e)) rethrow;
        final cause = e.cause! as ModelApiException;
        _log({
          'event': 'draft_backup',
          'from': models[i].model,
          'to': models[i + 1].model,
          'cause': '${cause.statusCode} ${cause.type}',
        });
      }
    }
  }

  /// Whether the provider refused the request itself, before any model
  /// looked at the job.
  static bool turnedAway(DraftFailed e) {
    final cause = e.cause;
    return !e.refused &&
        cause is ModelApiException &&
        (cause.isTransient ||
            const {401, 403, 404, 429}.contains(cause.statusCode));
  }
}

/// The drafter the server runs: the main model with its backups behind it,
/// or sample drafts when the config asks for them.
QuoteDrafter drafterFromConfig(ServerConfig config, {LogSink? log}) {
  if (config.fakeModel) return DemoDrafter();
  final main = (
    model: config.draftModel,
    drafter: _drafterFor(config, (
      provider: config.aiProvider,
      model: config.draftModel,
    )),
  );
  if (config.backupModels.isEmpty) return main.drafter;
  return BackupDrafter([
    main,
    for (final backup in config.backupModels)
      (model: backup.model, drafter: _drafterFor(config, backup)),
  ], log: log);
}

/// A model from the main provider keeps the main model's settings; one from
/// another provider gets that provider's defaults.
QuoteDrafter _drafterFor(ServerConfig c, ModelRef m) {
  final sameProvider = m.provider == c.aiProvider;
  return switch (m.provider) {
    // Holds the free-tier limits even when Groq is only a backup.
    'groq' => GroqDrafter(
      api: GroqClient(apiKey: c.groqApiKey!, baseUrl: c.groqBaseUrl),
      config: c.groqDrafter.copyWith(model: m.model),
    ),
    'gemini' => GeminiDrafter(
      api: GeminiClient(apiKey: c.geminiApiKey!, baseUrl: c.geminiBaseUrl),
      config: (sameProvider ? c.geminiDrafter : const GeminiDrafterConfig())
          .copyWith(model: m.model),
    ),
    _ => Drafter(
      api: ClaudeClient(
        apiKey: c.anthropicApiKey!,
        baseUrl: c.anthropicBaseUrl,
      ),
      config: DrafterConfig(
        model: m.model,
        effort: sameProvider ? c.drafter.effort : 'high',
        maxTokens: sameProvider ? c.drafter.maxTokens : 32000,
        // Refusal fallbacks are offered on the Opus and Fable models.
        useFallbacks:
            c.drafter.useFallbacks &&
            (m.model.startsWith('claude-opus') ||
                m.model.startsWith('claude-fable')),
      ),
    ),
  };
}
