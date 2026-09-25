import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('request body', () {
    final body = Drafter(
      api: FakeMessagesApi([]),
    ).buildRequestBody(draftRequest(), userId: 'install_1');

    test('uses Opus 5.5 with adaptive thinking and structured output', () {
      expect(body['model'], 'claude-opus-5-5');
      expect(body['max_tokens'], 32000);
      expect(body['thinking'], {'type': 'adaptive'});
      final output = body['output_config'] as Map;
      expect(output['effort'], 'high');
      expect((output['format'] as Map)['type'], 'json_schema');
      expect((output['format'] as Map)['schema'], same(draftSchema));
      expect(body['fallbacks'], 'default');
      expect(body['metadata'], {'user_id': 'install_1'});
      expect(body.containsKey('temperature'), isFalse);
    });

    test('caches the system prompt', () {
      final system = (body['system'] as List).single as Map;
      expect(system['text'], systemPrompt);
      expect(system['cache_control'], {'type': 'ephemeral'});
    });

    test('sends photos first, labeled, then the job context', () {
      final content =
          ((body['messages'] as List).single as Map)['content'] as List;
      expect(content, hasLength(5));
      expect((content[0] as Map)['text'], 'Photo 1:');
      final image = content[1] as Map;
      expect(image['type'], 'image');
      expect((image['source'] as Map)['media_type'], 'image/jpeg');
      expect((content[2] as Map)['text'], 'Photo 2:');
      final context = (content.last as Map)['text'] as String;
      expect(context, contains('Oak & Iron Fence Co.'));
      expect(context, contains('Customer wants cedar'));
    });

    test('fallbacks can be turned off', () {
      final b = Drafter(
        api: FakeMessagesApi([]),
        config: const DrafterConfig(useFallbacks: false, effort: 'medium'),
      ).buildRequestBody(draftRequest());
      expect(b.containsKey('fallbacks'), isFalse);
      expect(b.containsKey('metadata'), isFalse);
      expect((b['output_config'] as Map)['effort'], 'medium');
    });
  });

  group('draft', () {
    test('parses a structured draft and records usage', () async {
      final api = FakeMessagesApi([message(draft: draftJson())]);
      final d = await Drafter(api: api).draft(draftRequest());
      expect(d.draft.isUsable, isTrue);
      expect(d.draft.tiers.map((t) => t.id), ['pine', 'cedar', 'cedar_cap']);
      expect(d.model, 'claude-opus-5-5');
      expect(d.demo, isFalse);
      expect(d.stats.attempts, 1);
      expect(d.stats.inputTokens, 9000);
      // 9000 in at \$4, 6000 out at \$20, 3000 cache reads at \$0.20 / MTok.
      expect(d.stats.estimatedCostUsd, closeTo(0.1566, 1e-6));
      expect(api.betaHeaders.single, [Drafter.fallbackBeta]);
    });

    test('retries once on malformed output', () async {
      final api = FakeMessagesApi([
        message(rawText: '{"items": ['),
        message(draft: draftJson()),
      ]);
      final d = await Drafter(api: api).draft(draftRequest());
      expect(d.draft.isUsable, isTrue);
      expect(d.stats.attempts, 2);
      expect(d.stats.malformed, 1);
    });

    test('retries once when output is truncated, then gives up', () async {
      final api = FakeMessagesApi([
        message(rawText: '{}', stopReason: 'max_tokens'),
        message(rawText: '[1,2]'),
      ]);
      await expectLater(
        Drafter(api: api).draft(draftRequest()),
        throwsA(isA<DraftFailed>().having((e) => e.refused, 'refused', false)),
      );
      expect(api.requests, hasLength(2));
    });

    test('a refusal fails without retrying', () async {
      final api = FakeMessagesApi([refusal()]);
      await expectLater(
        Drafter(api: api).draft(draftRequest()),
        throwsA(isA<DraftFailed>().having((e) => e.refused, 'refused', true)),
      );
      expect(api.requests, hasLength(1));
    });

    test('API errors carry the cause', () async {
      final api = FakeMessagesApi([
        ClaudeApiException(529, 'overloaded_error', 'Overloaded'),
      ]);
      await expectLater(
        Drafter(api: api).draft(draftRequest()),
        throwsA(
          isA<DraftFailed>().having(
            (e) => (e.cause as ClaudeApiException).isTransient,
            'transient',
            isTrue,
          ),
        ),
      );
    });

    test('unknown models have no cost estimate', () {
      final stats = DraftStats()..add(message(model: 'mystery-model'));
      expect(stats.estimatedCostUsd, isNull);
    });
  });

  test('demo drafter picks the sample for the trade', () async {
    final d = await DemoDrafter(delay: Duration.zero).draft(draftRequest());
    expect(d.demo, isTrue);
    expect(d.draft.title, SampleJob.fence.draft.title);
    final json = d.toJson();
    expect(json['prompt_version'], promptVersion);
    expect(
      AiDraft.fromJson(json['draft'] as Map<String, Object?>).isUsable,
      isTrue,
    );
  });
}
