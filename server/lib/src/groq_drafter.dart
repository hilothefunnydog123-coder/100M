import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_core/photo_pipeline.dart';

import 'draft_schema.dart';
import 'drafter.dart';
import 'groq_client.dart';
import 'prompt.dart';

class GroqDrafterConfig {
  const GroqDrafterConfig({
    this.model = defaultModel,
    this.effort = 'medium',
    this.maxTokens = 16000,
    this.maxPhotos = 3,
    this.maxPhotoBytes = 900 * 1024,
    this.requestTokenLimit,
  });

  /// Fits Groq's free tier, which rejects any request whose prompt plus
  /// `max_completion_tokens` is over 8,000 tokens: one photo (2,048 tokens),
  /// light reasoning, and whatever room is left for the answer.
  static const freeTier = GroqDrafterConfig(
    effort: 'low',
    maxTokens: 4000,
    maxPhotos: 1,
    requestTokenLimit: 8000,
  );

  /// Groq's model that reads photos, as of September 2026.
  static const defaultModel = 'qwen/qwen3.8-27b';

  static const efforts = {'low', 'medium', 'high'};

  final String model;

  /// `reasoning_effort`, one of [efforts].
  final String effort;

  /// `max_completion_tokens`: reasoning plus the answer.
  final int maxTokens;

  /// Groq takes at most 3 images per request; later photos are left out.
  final int maxPhotos;

  /// Inline images are capped at 4 MB per request, so photos bigger than
  /// this are re-encoded smaller first.
  final int maxPhotoBytes;

  /// When set, `max_completion_tokens` shrinks so the whole request stays
  /// under this many tokens (Groq counts it before the model writes a word).
  final int? requestTokenLimit;

  GroqDrafterConfig copyWith({String? model, String? effort, int? maxTokens}) =>
      GroqDrafterConfig(
        model: model ?? this.model,
        effort: effort ?? this.effort,
        maxTokens: maxTokens ?? this.maxTokens,
        maxPhotos: maxPhotos,
        maxPhotoBytes: maxPhotoBytes,
        requestTokenLimit: requestTokenLimit,
      );
}

/// The same instructions Claude gets, plus the answer's shape: JSON mode
/// guarantees valid JSON, not our fields.
final groqSystemPrompt =
    '''
$systemPrompt

## Answer format
Reply with one JSON object and nothing else. Use exactly these fields, in this order, and fill in every one: "", [], or 0 when a field doesn't apply. Quantities, hours, and costs are plain numbers with no units or dollar signs.
${schemaShape(draftSchema)}''';

/// Drafts quotes with an open-weights vision model on Groq, through its
/// OpenAI-compatible API. Same prompt and parser as [Drafter], so the two
/// can be compared case for case with `bin/eval.dart`.
class GroqDrafter implements QuoteDrafter {
  GroqDrafter({
    required ChatCompletionsApi api,
    this.config = const GroqDrafterConfig(),
  }) : _api = api;

  /// Groq counts each image as this many input tokens.
  static const tokensPerImage = 2048;

  final ChatCompletionsApi _api;
  final GroqDrafterConfig config;

  Future<Map<String, Object?>> buildRequestBody(DraftRequest request) async {
    final photos = [
      for (final photo in request.photos.take(config.maxPhotos))
        await _fit(photo),
    ];
    final sent = DraftRequest(
      profile: request.profile,
      rates: request.rates,
      photos: photos,
      note: request.note,
    );
    final content = [
      for (final (i, photo) in photos.indexed) ...[
        {'type': 'text', 'text': 'Photo ${i + 1}:'},
        {
          'type': 'image_url',
          'image_url': {
            'url':
                'data:${photo.mediaType};base64,${base64Encode(photo.bytes)}',
          },
        },
      ],
      if (request.photos.length > photos.length)
        {
          'type': 'text',
          'text':
              'The owner took ${request.photos.length} photos; only these '
              '${photos.length} could be sent, so parts of the job may not be '
              'shown.',
        },
      {'type': 'text', 'text': describeJob(sent)},
    ];

    var maxTokens = config.maxTokens;
    if (config.requestTokenLimit case final limit?) {
      maxTokens = math.min(maxTokens, limit - _estimatePrompt(content));
      if (maxTokens < 1000) {
        throw DraftFailed(
          'This job is too big for the Groq plan: its limit of $limit tokens '
          'per request leaves no room for the answer.',
        );
      }
    }
    return {
      'model': config.model,
      'messages': [
        {'role': 'system', 'content': groqSystemPrompt},
        {'role': 'user', 'content': content},
      ],
      'response_format': {'type': 'json_object'},
      'reasoning_effort': config.effort,
      'reasoning_format': 'hidden',
      'max_completion_tokens': maxTokens,
      'temperature': 0.6,
    };
  }

  /// Photos at a flat rate, text at a conservative 3.5 characters a token
  /// (Qwen spends a token on every digit), plus the chat template.
  int _estimatePrompt(List<Map<String, Object?>> content) {
    var images = 0;
    var chars = groqSystemPrompt.length;
    for (final part in content) {
      if (part['type'] == 'image_url') images++;
      if (part['text'] case final String text) chars += text.length;
    }
    return images * tokensPerImage + (chars / 3.5).ceil() + 100;
  }

  Future<JobPhoto> _fit(JobPhoto photo) async {
    if (photo.bytes.length <= config.maxPhotoBytes) return photo;
    final bytes = photo.bytes;
    try {
      final smaller = await Isolate.run(
        () => preparePhoto(bytes, maxDimension: 1536, jpegQuality: 80),
      );
      return JobPhoto(bytes: smaller.jpeg, mediaType: 'image/jpeg');
    } on FormatException {
      return photo; // Let the API judge a photo we can't decode.
    }
  }

  /// [userId] is not sent to Groq.
  @override
  Future<Draft> draft(DraftRequest request, {String? userId}) async {
    final watch = Stopwatch()..start();
    final stats = DraftStats();
    final body = await buildRequestBody(request);

    Object? lastError;
    // One retry when the output is truncated or isn't the JSON we asked for.
    for (var attempt = 0; attempt < 2; attempt++) {
      final ChatCompletion completion;
      try {
        completion = await _api.createChatCompletion(body);
      } on GroqApiException catch (e) {
        if (!e.invalidJson) {
          throw DraftFailed(
            e.tooLarge
                ? 'The request is bigger than the Groq plan allows.'
                : 'The model request failed.',
            cause: e,
          );
        }
        stats
          ..record(model: config.model)
          ..malformed += 1
          ..latency = watch.elapsed;
        lastError = e;
        continue;
      }
      stats
        ..record(
          model: completion.model,
          inputTokens: completion.promptTokens - completion.cachedTokens,
          outputTokens: completion.completionTokens,
          cacheReadTokens: completion.cachedTokens,
        )
        ..latency = watch.elapsed;

      if (completion.finishReason == 'content_filter') {
        stats.refusals++;
        throw DraftFailed('The model declined these photos.', refused: true);
      }
      if (completion.finishReason == 'length') {
        stats.malformed++;
        lastError = const FormatException('Output hit max_completion_tokens.');
        continue;
      }
      try {
        return Draft(
          parseDraftAnswer(completion.content),
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
