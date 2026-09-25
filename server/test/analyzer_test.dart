import 'package:spotcheck_core/spotcheck_core.dart';
import 'package:spotcheck_server/spotcheck_server.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('request body', () {
    test(
      'uses Opus 5.5, adaptive thinking, effort, schema, cache, fallbacks',
      () async {
        final api = FakeMessagesApi([message(assessment: assessmentJson())]);
        final analyzer = Analyzer(api: api);
        await analyzer.analyze(checkRequest(photos: 2), userId: 'install_123');

        final body = api.requests.single;
        expect(body['model'], 'claude-opus-5-5');
        expect(body['max_tokens'], 16000);
        expect(body['thinking'], {'type': 'adaptive'});
        expect(body.containsKey('temperature'), isFalse);
        final output = body['output_config'] as Map;
        expect(output['effort'], 'high');
        expect((output['format'] as Map)['type'], 'json_schema');
        expect((output['format'] as Map)['schema'], same(assessmentSchema));
        final system = (body['system'] as List).single as Map;
        expect(system['cache_control'], {'type': 'ephemeral'});
        expect(system['text'], systemPrompt);
        expect(body['fallbacks'], 'default');
        expect(api.betaHeaders.single, [Analyzer.fallbackBeta]);
        expect(body['metadata'], {'user_id': 'install_123'});
        expect(body.containsKey('tool_choice'), isFalse);

        // Photos come first, each introduced by a label; context text last.
        final content =
            ((body['messages'] as List).single as Map)['content'] as List;
        final types = [for (final b in content) (b as Map)['type']];
        expect(types, ['text', 'image', 'text', 'image', 'text']);
        final image = content[1] as Map;
        expect((image['source'] as Map)['media_type'], 'image/jpeg');
        expect((content.last as Map)['text'], contains('<check>'));
      },
    );

    test('can disable fallbacks', () async {
      final api = FakeMessagesApi([message(assessment: assessmentJson())]);
      final analyzer = Analyzer(
        api: api,
        config: const AnalyzerConfig(useFallbacks: false, effort: 'medium'),
      );
      await analyzer.analyze(checkRequest());
      expect(api.requests.single.containsKey('fallbacks'), isFalse);
      expect(api.betaHeaders.single, isEmpty);
      expect((api.requests.single['output_config'] as Map)['effort'], 'medium');
    });
  });

  group('results', () {
    test('merges the assessment with the safety rules', () async {
      final api = FakeMessagesApi([message(assessment: assessmentJson())]);
      final analysis = await Analyzer(api: api).analyze(
        checkRequest(
          answers: {
            'skin_kind': ['rash'],
            'general_symptoms': ['fever'],
          },
        ),
        id: 'chk_fixed',
      );
      final r = analysis.result;
      expect(r.id, 'chk_fixed');
      expect(r.status, CheckStatus.complete);
      expect(r.urgency, Urgency.soon);
      expect(r.escalatedBySafetyRules, isTrue);
      expect(r.model, 'claude-opus-5-5');
      expect(r.assessment!.possibilities.single.name, 'Eczema');
      expect(analysis.stats.attempts, 1);
      expect(analysis.stats.cacheReadTokens, 2400);
      expect(analysis.stats.estimatedCostUsd, closeTo(0.02328, 1e-6));
    });

    test('ignores thinking and fallback blocks when reading JSON', () async {
      final api = FakeMessagesApi([
        message(
          assessment: assessmentJson(),
          model: 'claude-opus-5',
          extraBlocks: [
            {
              'type': 'fallback',
              'from': {'model': 'claude-opus-5-5'},
              'to': {'model': 'claude-opus-5'},
            },
          ],
        ),
      ]);
      final r = (await Analyzer(api: api).analyze(checkRequest())).result;
      expect(r.status, CheckStatus.complete);
      expect(r.model, 'claude-opus-5');
    });

    test('an unusable photo becomes a retake', () async {
      final api = FakeMessagesApi([
        message(assessment: assessmentJson(usable: false)),
      ]);
      final r = (await Analyzer(api: api).analyze(checkRequest())).result;
      expect(r.status, CheckStatus.retake);
      expect(r.message, contains('steady'));
    });

    test(
      'a refusal becomes a declined result that keeps the rule floor',
      () async {
        final api = FakeMessagesApi([refusal()]);
        final analysis = await Analyzer(api: api).analyze(
          checkRequest(
            site: BodySite.eye,
            answers: {
              'eye_symptoms': ['chemical'],
            },
          ),
        );
        expect(analysis.result.status, CheckStatus.declined);
        expect(analysis.result.urgency, Urgency.emergency);
        expect(analysis.stats.refusals, 1);
        expect(api.requests, hasLength(1), reason: 'refusals are not retried');
      },
    );

    test('retries once on malformed output', () async {
      final api = FakeMessagesApi([
        message(rawText: '{"not": "complete'),
        message(assessment: assessmentJson()),
      ]);
      final analysis = await Analyzer(api: api).analyze(checkRequest());
      expect(analysis.result.status, CheckStatus.complete);
      expect(analysis.stats.malformed, 1);
      expect(analysis.stats.attempts, 2);
    });

    test('retries once when output hits max_tokens', () async {
      final api = FakeMessagesApi([
        message(rawText: '{"image_quality"', stopReason: 'max_tokens'),
        message(assessment: assessmentJson()),
      ]);
      final analysis = await Analyzer(api: api).analyze(checkRequest());
      expect(analysis.result.status, CheckStatus.complete);
      expect(api.requests, hasLength(2));
    });

    test('fails after two malformed outputs', () async {
      final api = FakeMessagesApi([
        message(rawText: 'not json'),
        message(assessment: {'urgency': 'soonish'}),
      ]);
      expect(
        () => Analyzer(api: api).analyze(checkRequest()),
        throwsA(isA<AnalysisFailed>()),
      );
    });

    test('surfaces API errors as AnalysisFailed with the cause', () async {
      final api = FakeMessagesApi([
        ClaudeApiException(529, 'overloaded_error', 'Overloaded'),
      ]);
      await expectLater(
        Analyzer(api: api).analyze(checkRequest()),
        throwsA(
          isA<AnalysisFailed>().having(
            (e) => e.cause,
            'cause',
            isA<ClaudeApiException>(),
          ),
        ),
      );
    });
  });

  group('ensemble', () {
    test('combines runs and takes the most cautious urgency', () async {
      final api = FakeMessagesApi([
        message(assessment: assessmentJson()),
        message(
          assessment: assessmentJson(
            urgency: 'soon',
            careSetting: 'primary_care',
          ),
        ),
        message(assessment: assessmentJson()),
      ]);
      final analysis = await Analyzer(
        api: api,
        config: const AnalyzerConfig(ensembleSize: 3),
      ).analyze(checkRequest());
      expect(api.requests, hasLength(3));
      expect(analysis.result.urgency, Urgency.soon);
      expect(analysis.result.careSetting, CareSetting.primaryCare);
      expect(analysis.stats.attempts, 3);
    });

    test('still succeeds when one run refuses', () async {
      final api = FakeMessagesApi([
        refusal(),
        message(assessment: assessmentJson()),
      ]);
      final analysis = await Analyzer(
        api: api,
        config: const AnalyzerConfig(ensembleSize: 2),
      ).analyze(checkRequest());
      expect(analysis.result.status, CheckStatus.complete);
      expect(analysis.stats.refusals, 1);
    });
  });

  test('DemoAnalyzer flags its results', () async {
    final analysis = await DemoAnalyzer(delay: Duration.zero).analyze(
      checkRequest(
        answers: {
          'skin_kind': ['mole'],
          'mole_features': ['asymmetric'],
        },
      ),
    );
    expect(analysis.result.demo, isTrue);
    expect(analysis.result.urgency, Urgency.routine);
    expect(analysis.result.assessment!.possibilities.first.name, 'Common mole');
  });
}
