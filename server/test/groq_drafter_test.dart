import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

import 'fakes.dart';

List<Map<String, Object?>> userContent(Map<String, Object?> body) =>
    [
          for (final m in body['messages']! as List)
            if ((m as Map)['role'] == 'user') m,
        ].single['content']!
        as List<Map<String, Object?>>;

List<String> imageUrls(Map<String, Object?> body) => [
  for (final part in userContent(body))
    if (part['type'] == 'image_url')
      (part['image_url']! as Map)['url'] as String,
];

Uint8List noisyJpeg(int width, int height) {
  final random = Random(7);
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel
      ..r = random.nextInt(256)
      ..g = random.nextInt(256)
      ..b = random.nextInt(256);
  }
  return img.encodeJpg(image, quality: 95);
}

void main() {
  test('schemaShape renders fields, lists, and choices compactly', () {
    final shape = schemaShape({
      'type': 'object',
      'properties': {
        'a': {'type': 'string'},
        'b': {
          'type': 'array',
          'items': {'type': 'number'},
        },
        'c': {
          'type': 'string',
          'enum': ['x', 'y'],
        },
      },
    });
    expect(shape, '{"a": string, "b": [number], "c": "x"|"y"}');
    final full = schemaShape(draftSchema);
    for (final key in draftSchema['required']! as List) {
      expect(full, contains('"$key": '));
    }
    expect(full.length, lessThan(jsonEncode(draftSchema).length / 2));
  });

  group('request body', () {
    test('asks Qwen for JSON with the same prompt as Claude', () async {
      final body = await GroqDrafter(
        api: FakeChatApi([]),
      ).buildRequestBody(draftRequest());
      expect(body['model'], 'qwen/qwen3.8-27b');
      expect(body['response_format'], {'type': 'json_object'});
      expect(body['reasoning_effort'], 'medium');
      expect(body['reasoning_format'], 'hidden');
      expect(body['max_completion_tokens'], 16000);
      expect(body.containsKey('user'), isFalse);

      final system = (body['messages']! as List).first as Map;
      expect(system['role'], 'system');
      expect(system['content'], groqSystemPrompt);
      expect(groqSystemPrompt, startsWith(systemPrompt));
      expect(groqSystemPrompt, contains('"photos_usable": boolean'));
    });

    test('sends photos first, labeled, then the job context', () async {
      final body = await GroqDrafter(
        api: FakeChatApi([]),
      ).buildRequestBody(draftRequest());
      final content = userContent(body);
      expect(content, hasLength(5));
      expect(content[0]['text'], 'Photo 1:');
      expect(
        imageUrls(body).first,
        'data:image/jpeg;base64,${base64Encode(jpegBytes)}',
      );
      expect(content[2]['text'], 'Photo 2:');
      final context = content.last['text']! as String;
      expect(context, contains('Oak & Iron Fence Co.'));
      expect(context, contains('Customer wants cedar'));
      expect(context, contains('from the 2 photos above'));
    });

    test('sends at most three photos and says so', () async {
      final body = await GroqDrafter(
        api: FakeChatApi([]),
      ).buildRequestBody(draftRequest(photos: 5));
      expect(imageUrls(body), hasLength(3));
      final texts = [for (final p in userContent(body)) ?p['text'] as String?];
      expect(
        texts,
        contains(startsWith('The owner took 5 photos; only these 3')),
      );
      expect(texts.last, contains('from the 3 photos above'));
    });

    test('the free tier fits the whole request in 8,000 tokens', () async {
      final body = await GroqDrafter(
        api: FakeChatApi([]),
        config: GroqDrafterConfig.freeTier,
      ).buildRequestBody(draftRequest(photos: 4));
      expect(imageUrls(body), hasLength(1));
      expect(body['reasoning_effort'], 'low');
      // 2,048 for the photo and about 2,700 for the text leave ~3,200.
      expect(body['max_completion_tokens'], inInclusiveRange(2800, 3600));

      final long = await GroqDrafter(
        api: FakeChatApi([]),
        config: GroqDrafterConfig.freeTier,
      ).buildRequestBody(draftRequest(note: 'x' * 1000));
      expect(
        long['max_completion_tokens'] as int,
        lessThan(body['max_completion_tokens'] as int),
      );
    });

    test('a request with no room left for the answer fails early', () async {
      final drafter = GroqDrafter(
        api: FakeChatApi([]),
        config: const GroqDrafterConfig(maxPhotos: 1, requestTokenLimit: 5000),
      );
      await expectLater(
        drafter.draft(draftRequest()),
        throwsA(
          isA<DraftFailed>().having(
            (e) => e.message,
            'message',
            contains('5000 tokens'),
          ),
        ),
      );
    });

    test('re-encodes photos too big for inline images', () async {
      final big = noisyJpeg(320, 240);
      final request = DraftRequest(
        profile: const BusinessProfile(name: 'Brightline Painting'),
        rates: Rates.forTrade(Trade.painting),
        photos: [
          JobPhoto(bytes: big, mediaType: 'image/jpeg'),
          JobPhoto(bytes: Uint8List(3000), mediaType: 'image/jpeg'),
        ],
      );
      final body = await GroqDrafter(
        api: FakeChatApi([]),
        config: const GroqDrafterConfig(maxPhotoBytes: 2000),
      ).buildRequestBody(request);
      final urls = imageUrls(body);
      final sent = base64Decode(urls[0].split(',').last);
      expect(sent.length, lessThan(big.length));
      expect(sent.sublist(0, 2), [0xFF, 0xD8]);
      // A photo that can't be decoded goes as is; the API will judge it.
      expect(base64Decode(urls[1].split(',').last), Uint8List(3000));
    });
  });

  group('draft', () {
    test('parses a draft and records usage and cost', () async {
      final api = FakeChatApi([chatReply(draft: draftJson())]);
      final d = await GroqDrafter(api: api).draft(draftRequest());
      expect(d.draft.isUsable, isTrue);
      expect(d.draft.tiers.map((t) => t.id), ['pine', 'cedar', 'cedar_cap']);
      expect(d.model, 'qwen/qwen3.8-27b');
      expect(d.demo, isFalse);
      expect(d.stats.attempts, 1);
      expect(d.stats.inputTokens, 8000);
      expect(d.stats.outputTokens, 4000);
      // 8,000 in at \$0.80 and 4,000 out at \$4 per million tokens.
      expect(d.stats.estimatedCostUsd, closeTo(0.0224, 1e-9));
    });

    test('counts cached input separately', () async {
      final api = FakeChatApi([
        chatReply(draft: draftJson(), cachedTokens: 2000),
      ]);
      final d = await GroqDrafter(api: api).draft(draftRequest());
      expect(d.stats.inputTokens, 6000);
      expect(d.stats.cacheReadTokens, 2000);
    });

    test('retries once when JSON mode rejects the output', () async {
      final api = FakeChatApi([
        GroqApiException(
          400,
          'invalid_request_error',
          'Failed to generate JSON.',
          code: 'json_validate_failed',
        ),
        chatReply(draft: draftJson()),
      ]);
      final d = await GroqDrafter(api: api).draft(draftRequest());
      expect(d.draft.isUsable, isTrue);
      expect(d.stats.attempts, 2);
      expect(d.stats.malformed, 1);
    });

    test('an answer missing fields is malformed, not empty', () async {
      final api = FakeChatApi([
        chatReply(content: '{"line_items": []}'),
        chatReply(draft: draftJson()),
      ]);
      final d = await GroqDrafter(api: api).draft(draftRequest());
      expect(d.draft.isUsable, isTrue);
      expect(d.stats.malformed, 1);
      expect(() => parseDraftAnswer('[1, 2]'), throwsA(isA<FormatException>()));
    });

    test('retries once when output is truncated, then gives up', () async {
      final api = FakeChatApi([
        chatReply(content: '{', finishReason: 'length'),
        chatReply(content: '{"title": "Fence"}'),
      ]);
      await expectLater(
        GroqDrafter(api: api).draft(draftRequest()),
        throwsA(isA<DraftFailed>().having((e) => e.refused, 'refused', false)),
      );
      expect(api.requests, hasLength(2));
    });

    test('a content filter stop is a refusal, without retrying', () async {
      final api = FakeChatApi([
        chatReply(content: '', finishReason: 'content_filter'),
      ]);
      await expectLater(
        GroqDrafter(api: api).draft(draftRequest()),
        throwsA(isA<DraftFailed>().having((e) => e.refused, 'refused', true)),
      );
      expect(api.requests, hasLength(1));
    });

    test('API errors carry the cause', () async {
      final limited = FakeChatApi([
        GroqApiException(429, 'tokens', 'Rate limit reached'),
      ]);
      await expectLater(
        GroqDrafter(api: limited).draft(draftRequest()),
        throwsA(
          isA<DraftFailed>().having(
            (e) => (e.cause! as ModelApiException).isTransient,
            'transient',
            isTrue,
          ),
        ),
      );
      final tooBig = FakeChatApi([
        GroqApiException(413, 'tokens', 'Request too large'),
      ]);
      await expectLater(
        GroqDrafter(api: tooBig).draft(draftRequest()),
        throwsA(
          isA<DraftFailed>().having(
            (e) => e.message,
            'message',
            contains('bigger than the Groq plan allows'),
          ),
        ),
      );
    });
  });
}
