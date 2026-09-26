import 'dart:convert';

import 'package:jobwalk_core/jobwalk_core.dart';

import 'draft_schema.dart';
import 'drafter.dart';
import 'gemini_client.dart';
import 'prompt.dart';

class GeminiDrafterConfig {
  const GeminiDrafterConfig({
    this.model = defaultModel,
    this.effort = 'high',
    this.maxTokens = 32000,
  });

  /// Gemini's newest Flash model, as of September 2026.
  static const defaultModel = 'gemini-3.8-flash';

  static const efforts = {'low', 'medium', 'high'};

  final String model;

  /// `thinkingLevel`, one of [efforts]. The model defaults to medium;
  /// measuring and pricing a job rewards careful reasoning, as with Claude.
  final String effort;

  /// `maxOutputTokens`: thinking plus the answer.
  final int maxTokens;

  GeminiDrafterConfig copyWith({
    String? model,
    String? effort,
    int? maxTokens,
  }) => GeminiDrafterConfig(
    model: model ?? this.model,
    effort: effort ?? this.effort,
    maxTokens: maxTokens ?? this.maxTokens,
  );
}

/// Drafts quotes with Gemini through `generateContent`. Same prompt as
/// [Drafter], and Gemini enforces the same answer schema, so the providers
/// can be compared case for case with `bin/eval.dart`.
class GeminiDrafter implements QuoteDrafter {
  GeminiDrafter({
    required GenerateContentApi api,
    this.config = const GeminiDrafterConfig(),
  }) : _api = api;

  final GenerateContentApi _api;
  final GeminiDrafterConfig config;

  /// Photos first, labeled, then the job context, as with Claude.
  Map<String, Object?> buildRequestBody(DraftRequest request) => {
    'systemInstruction': {
      'parts': [
        {'text': systemPrompt},
      ],
    },
    'contents': [
      {
        'role': 'user',
        'parts': [
          for (final (i, photo) in request.photos.indexed) ...[
            {'text': 'Photo ${i + 1}:'},
            {
              'inlineData': {
                'mimeType': photo.mediaType,
                'data': base64Encode(photo.bytes),
              },
            },
          ],
          {'text': describeJob(request)},
        ],
      },
    ],
    'generationConfig': {
      'responseMimeType': 'application/json',
      'responseJsonSchema': draftSchema,
      'maxOutputTokens': config.maxTokens,
      'thinkingConfig': {'thinkingLevel': config.effort},
    },
  };

  /// [userId] is not sent to Google.
  @override
  Future<Draft> draft(DraftRequest request, {String? userId}) async {
    final watch = Stopwatch()..start();
    final stats = DraftStats();
    final body = buildRequestBody(request);

    Object? lastError;
    // One retry when the output is truncated or can't be parsed.
    for (var attempt = 0; attempt < 2; attempt++) {
      final GeminiResponse response;
      try {
        response = await _api.generateContent(config.model, body);
      } on GeminiApiException catch (e) {
        throw DraftFailed(
          e.dailyQuota
              ? "Gemini's daily limit for this model is used up. It resets "
                    'at midnight Pacific time.'
              : 'The model request failed.',
          cause: e,
        );
      }
      stats
        ..record(
          model: config.model,
          inputTokens: response.promptTokens - response.cachedTokens,
          outputTokens: response.answerTokens + response.thoughtTokens,
          cacheReadTokens: response.cachedTokens,
        )
        ..latency = watch.elapsed;

      if (response.blocked) {
        stats.refusals++;
        throw DraftFailed('The model declined these photos.', refused: true);
      }
      if (response.finishReason == 'MAX_TOKENS') {
        stats.malformed++;
        lastError = const FormatException('Output hit maxOutputTokens.');
        continue;
      }
      try {
        return Draft(
          parseDraftAnswer(response.text),
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
