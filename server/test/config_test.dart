import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

void main() {
  test('defaults to Opus 5.5 at high effort', () {
    final c = ServerConfig.fromEnvironment({'ANTHROPIC_API_KEY': 'k'});
    expect(c.drafter.model, 'claude-opus-5-5');
    expect(c.drafter.effort, 'high');
    expect(c.drafter.maxTokens, 32000);
    expect(c.drafter.useFallbacks, isTrue);
    expect(c.port, 8080);
    expect(c.dataDir, 'data');
    expect(c.publicBaseUrl, isNull);
    expect(c.apiBaseUrl, isNull);
  });

  test('ignores generic variables set by other tools', () {
    final c = ServerConfig.fromEnvironment({
      'ANTHROPIC_API_KEY': 'k',
      'CLAUDE_EFFORT': 'max',
      'CLAUDE_MODEL': 'something-else',
    });
    expect(c.drafter.effort, 'high');
    expect(c.drafter.model, 'claude-opus-5-5');
  });

  test('reads namespaced overrides', () {
    final c = ServerConfig.fromEnvironment({
      'ANTHROPIC_API_KEY': 'k',
      'ANTHROPIC_BASE_URL': 'https://proxy.example/anthropic',
      'JOBWALK_EFFORT': 'medium',
      'JOBWALK_MAX_TOKENS': '20000',
      'JOBWALK_FALLBACKS': 'false',
      'JOBWALK_PUBLIC_URL': 'https://jobwalk.app',
      'JOBWALK_DATA_DIR': '/data',
      'JOBWALK_CORS_ORIGINS': 'https://a.example, https://b.example',
      'JOBWALK_RATE_LIMIT_INSTALL_BURST': '3',
      'PORT': '9000',
    });
    expect(c.drafter.effort, 'medium');
    expect(c.drafter.maxTokens, 20000);
    expect(c.drafter.useFallbacks, isFalse);
    expect(c.publicBaseUrl.toString(), 'https://jobwalk.app');
    expect(c.apiBaseUrl.toString(), 'https://proxy.example/anthropic');
    expect(c.dataDir, '/data');
    expect(c.corsOrigins, ['https://a.example', 'https://b.example']);
    expect(c.installBurst, 3);
    expect(c.port, 9000);
  });

  test('fake mode needs no key', () {
    final c = ServerConfig.fromEnvironment({'JOBWALK_FAKE_MODEL': 'true'});
    expect(c.fakeModel, isTrue);
    expect(c.apiKey, isNull);
  });

  test('fails fast on bad configuration', () {
    expect(() => ServerConfig.fromEnvironment({}), throwsStateError);
    expect(
      () => ServerConfig.fromEnvironment({
        'ANTHROPIC_API_KEY': 'k',
        'JOBWALK_EFFORT': 'extreme',
      }),
      throwsStateError,
    );
    expect(
      () => ServerConfig.fromEnvironment({
        'ANTHROPIC_API_KEY': 'k',
        'JOBWALK_PUBLIC_URL': 'jobwalk.app',
      }),
      throwsStateError,
    );
  });
}
