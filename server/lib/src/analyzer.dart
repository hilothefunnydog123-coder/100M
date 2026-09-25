import 'dart:convert';

import 'package:spotcheck_core/spotcheck_core.dart';

import 'assessment_schema.dart';
import 'claude_client.dart';
import 'ensemble.dart';
import 'prompt.dart';

class AnalyzerConfig {
  const AnalyzerConfig({
    this.model = 'claude-opus-5-5',
    this.effort = 'high',
    this.maxTokens = 16000,
    this.useFallbacks = true,
    this.ensembleSize = 1,
  });

  /// Claude Opus 5.5 by default. Thinking is always on for this model;
  /// [effort] is the lever for depth, latency, and cost.
  final String model;

  /// `low` | `medium` | `high` | `xhigh` | `max`. The API default for Opus
  /// 5.5 is `medium`; triage is accuracy-sensitive, so this defaults higher.
  final String effort;

  /// Room for adaptive thinking plus the JSON reply.
  final int maxTokens;

  /// Opt in to server-side fallbacks so a classifier false positive on a
  /// medical photo is retried on another model instead of failing the check.
  final bool useFallbacks;

  /// Independent samples to combine (see [Ensemble]). 1 disables it.
  final int ensembleSize;
}

/// Raised when no usable assessment could be produced.
class AnalysisFailed implements Exception {
  AnalysisFailed(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'AnalysisFailed: $message${cause == null ? '' : ' ($cause)'}';
}

/// Token usage and cost for one analysis, across every attempt.
class AnalysisStats {
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

class Analysis {
  Analysis(this.result, this.stats);

  final CheckResult result;
  final AnalysisStats stats;
}

/// Turns a validated [CheckRequest] into a [CheckResult].
abstract interface class CheckAnalyzer {
  Future<Analysis> analyze(CheckRequest request, {String? id, String? userId});
}

class Analyzer implements CheckAnalyzer {
  Analyzer({
    required MessagesApi api,
    this.config = const AnalyzerConfig(),
    DateTime Function()? clock,
  }) : _api = api,
       _clock = clock ?? (() => DateTime.now().toUtc());

  /// Beta header for `fallbacks: "default"` (routes by refusal category).
  static const fallbackBeta = 'server-side-fallback-2026-07-01';

  final MessagesApi _api;
  final AnalyzerConfig config;
  final DateTime Function() _clock;

  Map<String, Object?> buildRequestBody(
    CheckRequest request,
    SafetyEvaluation safety, {
    String? userId,
  }) => {
    'model': config.model,
    'max_tokens': config.maxTokens,
    'thinking': {'type': 'adaptive'},
    'output_config': {
      'effort': config.effort,
      'format': {'type': 'json_schema', 'schema': assessmentSchema},
    },
    'system': [
      {
        'type': 'text',
        'text': systemPrompt,
        'cache_control': {'type': 'ephemeral'},
      },
    ],
    'messages': [
      {'role': 'user', 'content': buildUserContent(request, safety)},
    ],
    if (config.useFallbacks) 'fallbacks': 'default',
    if (userId != null) 'metadata': {'user_id': userId},
  };

  /// Analyzes a validated request. [userId] should be an opaque identifier
  /// (never personal information); it helps Anthropic detect abuse.
  @override
  Future<Analysis> analyze(
    CheckRequest request, {
    String? id,
    String? userId,
  }) async {
    final watch = Stopwatch()..start();
    final stats = AnalysisStats();
    final checkId = id ?? newId('chk');
    final safety = SafetyRules.evaluate(request.site, request.answers);
    final body = buildRequestBody(request, safety, userId: userId);

    final outcomes = await Future.wait([
      for (var i = 0; i < config.ensembleSize; i++) _run(body, stats),
    ]);
    stats.latency = watch.elapsed;

    final assessments = [
      for (final o in outcomes)
        if (o.assessment != null) o.assessment!,
    ];
    final model = stats.models.join(',');
    final createdAt = _clock();

    if (assessments.isEmpty) {
      if (outcomes.any((o) => o.refused)) {
        return Analysis(
          Triage.declined(
            id: checkId,
            safety: safety,
            createdAt: createdAt,
            model: model,
          ),
          stats,
        );
      }
      final error = outcomes
          .map((o) => o.error)
          .whereType<Object>()
          .firstOrNull;
      throw AnalysisFailed('No valid assessment was produced.', cause: error);
    }

    return Analysis(
      Triage.merge(
        id: checkId,
        assessment: Ensemble.combine(assessments),
        safety: safety,
        createdAt: createdAt,
        model: model,
      ),
      stats,
    );
  }

  /// One sample, with a single retry if the output is truncated or can't be
  /// parsed. API errors are captured so other ensemble runs can still win.
  Future<_Outcome> _run(Map<String, Object?> body, AnalysisStats stats) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      final ClaudeMessage message;
      try {
        message = await _api.createMessage(
          body,
          betas: config.useFallbacks ? const [fallbackBeta] : const [],
        );
      } on ClaudeApiException catch (e) {
        return _Outcome(error: e);
      }
      stats.add(message);

      // Always check the stop reason before reading content.
      if (message.refused) {
        stats.refusals++;
        return _Outcome(refused: true);
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
        return _Outcome(assessment: ModelAssessment.fromJson(decoded));
      } on FormatException catch (e) {
        stats.malformed++;
        lastError = e;
      }
    }
    return _Outcome(error: lastError);
  }
}

class _Outcome {
  _Outcome({this.assessment, this.refused = false, this.error});

  final ModelAssessment? assessment;
  final bool refused;
  final Object? error;
}

/// Serves canned demo assessments without calling Claude, for local
/// development without an API key. Every result is flagged `demo`.
class DemoAnalyzer implements CheckAnalyzer {
  DemoAnalyzer({this.delay = const Duration(seconds: 2)});

  final Duration delay;

  @override
  Future<Analysis> analyze(
    CheckRequest request, {
    String? id,
    String? userId,
  }) async {
    await Future<void>.delayed(delay);
    final result = Triage.merge(
      id: id ?? newId('chk'),
      assessment: demoAssessmentFor(request.site, request.answers),
      safety: SafetyRules.evaluate(request.site, request.answers),
      createdAt: DateTime.now().toUtc(),
      model: 'demo',
      demo: true,
    );
    return Analysis(result, AnalysisStats());
  }
}
