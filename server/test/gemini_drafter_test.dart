import 'dart:convert';

import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('request body', () {
    final body = GeminiDrafter(
      api: FakeGeminiApi([]),
    ).buildRequestBody(draftRequest());

    test('enforces the draft schema with the same prompt as Claude', () {
      final system = body['systemInstruction']! as Map;
      expect((system['parts'] as List).single, {'text': systemPrompt});
      final config = body['generationConfig']! as Map;
      expect(config['responseMimeType'], 'application/json');
      expect(config['responseJsonSchema'], same(draftSchema));
      expect(config['maxOutputTokens'], 32000);
      expect(config['thinkingConfig'], {'thinkingLevel': 'high'});
      expect(body.containsKey('safetySettings'), isFalse);
    });

    test('sends every photo first, labeled, then the job context', () {
      final parts =
          ((body['contents']! as List).single as Map)['parts'] as List;
      expect(parts, hasLength(5));
      expect(parts[0], {'text': 'Photo 1:'});
      expect(parts[1], {
        'inlineData': {
          'mimeType': 'image/jpeg',
          'data': base64Encode(jpegBytes),
        },
      });
      expect(parts[2], {'text': 'Photo 2:'});
      final context = (parts.last as Map)['text'] as String;
      expect(context, contains('Oak & Iron Fence Co.'));
      expect(context, contains('Customer wants cedar'));

      final eight = GeminiDrafter(
        api: FakeGeminiApi([]),
      ).buildRequestBody(draftRequest(photos: 8));
      final eightParts =
          ((eight['contents']! as List).single as Map)['parts'] as List;
      expect(
        eightParts.where((p) => (p as Map).containsKey('inlineData')),
        hasLength(8),
      );
    });
  });

  group('draft', () {
    test('parses a draft and records usage and cost', () async {
      final api = FakeGeminiApi([geminiReply(draft: draftJson())]);
      final d = await GeminiDrafter(api: api).draft(draftRequest());
      expect(api.requests.single.$1, 'gemini-3.8-flash');
      expect(d.draft.isUsable, isTrue);
      expect(d.draft.tiers.map((t) => t.id), ['pine', 'cedar', 'cedar_cap']);
      expect(d.model, 'gemini-3.8-flash');
      expect(d.stats.attempts, 1);
      expect(d.stats.inputTokens, 8000);
      // The answer plus the thinking behind it: 1,500 + 2,500.
      expect(d.stats.outputTokens, 4000);
      // 8,000 in at \$0.75 and 4,000 out at \$3.75 per million tokens.
      expect(d.stats.estimatedCostUsd, closeTo(0.021, 1e-9));
    });

    test('counts cached input separately', () async {
      final api = FakeGeminiApi([
        geminiReply(draft: draftJson(), cachedTokens: 3000),
      ]);
      final d = await GeminiDrafter(api: api).draft(draftRequest());
      expect(d.stats.inputTokens, 5000);
      expect(d.stats.cacheReadTokens, 3000);
    });

    test('retries once on malformed output', () async {
      final api = FakeGeminiApi([
        geminiReply(text: '{"items": ['),
        geminiReply(draft: draftJson()),
      ]);
      final d = await GeminiDrafter(api: api).draft(draftRequest());
      expect(d.draft.isUsable, isTrue);
      expect(d.stats.attempts, 2);
      expect(d.stats.malformed, 1);
    });

    test('retries once when output is truncated, then gives up', () async {
      final api = FakeGeminiApi([
        geminiReply(text: '{', finishReason: 'MAX_TOKENS'),
        geminiReply(finishReason: 'MAX_TOKENS'),
      ]);
      await expectLater(
        GeminiDrafter(api: api).draft(draftRequest()),
        throwsA(isA<DraftFailed>().having((e) => e.refused, 'refused', false)),
      );
      expect(api.requests, hasLength(2));
    });

    test('a safety block is a refusal, without retrying', () async {
      final api = FakeGeminiApi([
        GeminiResponse({
          'promptFeedback': {'blockReason': 'SAFETY'},
          'usageMetadata': {'promptTokenCount': 3000},
        }),
      ]);
      await expectLater(
        GeminiDrafter(api: api).draft(draftRequest()),
        throwsA(isA<DraftFailed>().having((e) => e.refused, 'refused', true)),
      );
      expect(api.requests, hasLength(1));
    });

    test('API errors carry the cause', () async {
      final busy = FakeGeminiApi([
        GeminiApiException(503, 'UNAVAILABLE', 'Overloaded'),
      ]);
      await expectLater(
        GeminiDrafter(api: busy).draft(draftRequest()),
        throwsA(
          isA<DraftFailed>().having(
            (e) => (e.cause! as ModelApiException).isTransient,
            'transient',
            isTrue,
          ),
        ),
      );
      final spent = FakeGeminiApi([
        GeminiApiException(
          429,
          'RESOURCE_EXHAUSTED',
          'Quota exceeded',
          dailyQuota: true,
        ),
      ]);
      await expectLater(
        GeminiDrafter(api: spent).draft(draftRequest()),
        throwsA(
          isA<DraftFailed>().having(
            (e) => e.message,
            'message',
            contains('daily limit'),
          ),
        ),
      );
    });
  });
}
