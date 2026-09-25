import 'package:spotcheck_server/spotcheck_server.dart';
import 'package:test/test.dart';

void main() {
  test('defaults to Opus 5.5 at high effort with fallbacks on', () {
    final c = ServerConfig.fromEnvironment({'ANTHROPIC_API_KEY': 'k'});
    expect(c.analyzer.model, 'claude-opus-5-5');
    expect(c.analyzer.effort, 'high');
    expect(c.analyzer.useFallbacks, isTrue);
    expect(c.analyzer.ensembleSize, 1);
    expect(c.port, 8080);
    expect(c.apiBaseUrl, isNull);
  });

  test('ignores generic variables set by other tools', () {
    final c = ServerConfig.fromEnvironment({
      'ANTHROPIC_API_KEY': 'k',
      'CLAUDE_EFFORT': 'max',
      'CLAUDE_MODEL': 'something-else',
    });
    expect(c.analyzer.effort, 'high');
    expect(c.analyzer.model, 'claude-opus-5-5');
  });

  test('reads namespaced overrides', () {
    final c = ServerConfig.fromEnvironment({
      'ANTHROPIC_API_KEY': 'k',
      'ANTHROPIC_BASE_URL': 'https://proxy.example',
      'SPOTCHECK_EFFORT': 'medium',
      'SPOTCHECK_ENSEMBLE_SIZE': '9',
      'SPOTCHECK_FALLBACKS': 'false',
      'SPOTCHECK_CORS_ORIGINS': 'https://a.example, https://b.example',
      'PORT': '9000',
    });
    expect(c.analyzer.effort, 'medium');
    expect(c.analyzer.ensembleSize, 5, reason: 'clamped');
    expect(c.analyzer.useFallbacks, isFalse);
    expect(c.corsOrigins, ['https://a.example', 'https://b.example']);
    expect(c.port, 9000);
    expect(c.apiBaseUrl.toString(), 'https://proxy.example');
  });

  test('requires an API key unless the fake model is on', () {
    expect(() => ServerConfig.fromEnvironment({}), throwsStateError);
    final c = ServerConfig.fromEnvironment({'SPOTCHECK_FAKE_MODEL': 'true'});
    expect(c.fakeModel, isTrue);
  });

  test('rejects unknown effort levels', () {
    expect(
      () => ServerConfig.fromEnvironment({
        'ANTHROPIC_API_KEY': 'k',
        'SPOTCHECK_EFFORT': 'extreme',
      }),
      throwsStateError,
    );
  });
}
