import 'dart:convert';

import 'package:jobwalk_core/jobwalk_core.dart';

import 'claude_client.dart';
import 'draft_schema.dart';
import 'prompt.dart';

class DrafterConfig {
  const DrafterConfig({
    this.model = 'claude-opus-5-5',
    this.effort = 'high',
    this.maxTokens = 32000,
    this.useFallbacks = true,
  });

  /// Claude Opus 5.5 by default. Thinking is always on for this model;
  /// [effort] is the lever for depth, latency, and cost.
  final String model;

  /// `low` | `medium` | `high` | `xhigh` | `max`. Measuring and pricing a
  /// job rewards careful reasoning, so this defaults to high.
  final String effort;

  /// Room for adaptive thinking plus a long quote.
  final int maxTokens;

  /// Opt in to server-side fallbacks so a refusal on one model is retried
  /// on another instead of failing the draft.
  final bool useFallbacks;
}

/// Raised when no usable draft could be produced.
class DraftFailed implements Exception {
  DraftFailed(this.message, {this.cause, this.refused = false});

  final String message;
  final Object? cause;
  final bool refused;

  @override
  String toString() =>
      'DraftFailed: $message${cause == null ? '' : ' ($cause)'}';
}

/// Token usage and cost for one draft, across every attempt.
class DraftStats {
  int attempts = 0;
  int refusals = 0;
  int malformed = 0;
  int inputTokens = 0;
  int outputTokens = 0;
  int cacheReadTokens = 0;
  int cacheWriteTokens = 0;
  final models = <String>{};
  Duration latency = Duration.zero;

  void add(ClaudeMessage m) {
    attempts++;
    inputTokens += m.inputTokens;
    outputTokens += m.outputTokens;
    cacheReadTokens += m.cacheReadTokens;
    cacheWriteTokens += m.cacheWriteTokens;
    if (m.model.isNotEmpty) models.add(m.model);
  }

  /// Estimated cost in USD from list prices, or null for unknown models.
  double? get estimatedCostUsd {
    if (models.isEmpty) return 0;
    double total = 0;
    for (final model in models) {
      final p = _pricesPerMTok[model];
      if (p == null) return null;
      // Split evenly if a fallback served part of the traffic; this is an
      // estimate for reporting, not billing.
      final share = 1 / models.length;
      total +=
          share *
          (inputTokens * p.$1 +
              outputTokens * p.$2 +
              cacheReadTokens * p.$3 +
              cacheWriteTokens * p.$4) /
          1e6;
    }
    return total;
  }

  Map<String, Object?> toJson() => {
    'attempts': attempts,
    'refusals': refusals,
    'malformed': malformed,
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    'cache_read_tokens': cacheReadTokens,
    'cache_write_tokens': cacheWriteTokens,
    'models': models.toList(),
    'latency_ms': latency.inMilliseconds,
    'estimated_cost_usd': estimatedCostUsd,
  };
}

/// (input, output, cache read, 5-minute cache write) USD per million tokens.
const _pricesPerMTok = <String, (double, double, double, double)>{
  'claude-opus-5-5': (4, 20, 0.20, 5),
  'claude-opus-5': (5, 25, 0.50, 6.25),
  'claude-opus-4-8': (5, 25, 0.50, 6.25),
  'claude-fable-5-1': (10, 50, 0.25, 12.5),
  'claude-sonnet-5': (2, 10, 0.20, 2.5),
  'claude-haiku-4-5': (1, 5, 0.10, 1.25),
};

class Draft {
  Draft(this.draft, this.stats, {this.model = '', this.demo = false});

  final AiDraft draft;
  final DraftStats stats;
  final String model;
  final bool demo;

  Map<String, Object?> toJson() => {
    'draft': draft.toJson(),
    'model': model,
    'demo': demo,
    'prompt_version': promptVersion,
  };
}

/// Turns job photos and the contractor's context into an [AiDraft].
abstract interface class QuoteDrafter {
  Future<Draft> draft(DraftRequest request, {String? userId});
}

class Drafter implements QuoteDrafter {
  Drafter({required MessagesApi api, this.config = const DrafterConfig()})
    : _api = api;

  /// Beta header for `fallbacks: "default"` (routes by refusal category).
  static const fallbackBeta = 'server-side-fallback-2026-07-01';

  final MessagesApi _api;
  final DrafterConfig config;

  Map<String, Object?> buildRequestBody(
    DraftRequest request, {
    String? userId,
  }) => {
    'model': config.model,
    'max_tokens': config.maxTokens,
    'thinking': {'type': 'adaptive'},
    'output_config': {
      'effort': config.effort,
      'format': {'type': 'json_schema', 'schema': draftSchema},
    },
    'system': [
      {
        'type': 'text',
        'text': systemPrompt,
        'cache_control': {'type': 'ephemeral'},
      },
    ],
    'messages': [
      {'role': 'user', 'content': buildUserContent(request)},
    ],
    if (config.useFallbacks) 'fallbacks': 'default',
    if (userId != null) 'metadata': {'user_id': userId},
  };

  /// Drafts a quote. [userId] should be an opaque identifier (never
  /// personal information); it helps Anthropic detect abuse.
  @override
  Future<Draft> draft(DraftRequest request, {String? userId}) async {
    final watch = Stopwatch()..start();
    final stats = DraftStats();
    final body = buildRequestBody(request, userId: userId);

    Object? lastError;
    // One retry when the output is truncated or can't be parsed.
    for (var attempt = 0; attempt < 2; attempt++) {
      final ClaudeMessage message;
      try {
        message = await _api.createMessage(
          body,
          betas: config.useFallbacks ? const [fallbackBeta] : const [],
        );
      } on ClaudeApiException catch (e) {
        throw DraftFailed('The model request failed.', cause: e);
      }
      stats
        ..add(message)
        ..latency = watch.elapsed;

      // Always check the stop reason before reading content.
      if (message.refused) {
        stats.refusals++;
        throw DraftFailed('The model declined these photos.', refused: true);
      }
      if (message.stopReason == 'max_tokens') {
        stats.malformed++;
        lastError = const FormatException('Output hit max_tokens.');
        continue;
      }
      try {
        final decoded = jsonDecode(message.text);
        if (decoded is! Map<String, Object?>) {
          throw const FormatException('Output is not a JSON object.');
        }
        return Draft(
          AiDraft.fromJson(decoded),
          stats,
          model: stats.models.join(','),
        );
      } on FormatException catch (e) {
        stats.malformed++;
        lastError = e;
      }
    }
    throw DraftFailed('No valid draft was produced.', cause: lastError);
  }
}

/// Serves the sample drafts without calling Claude, for local development
/// without an API key. Every draft is flagged `demo`.
class DemoDrafter implements QuoteDrafter {
  DemoDrafter({this.delay = const Duration(seconds: 3)});

  final Duration delay;

  @override
  Future<Draft> draft(DraftRequest request, {String? userId}) async {
    await Future<void>.delayed(delay);
    final sample = SampleJob.forTrade(request.profile.primaryTrade);
    return Draft(sample.draft, DraftStats(), model: 'demo', demo: true);
  }
}
