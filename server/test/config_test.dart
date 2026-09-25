import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

void main() {
  const production = {
    'JOBWALK_ENV': 'production',
    'DATABASE_URL': 'postgres://u:p@db.example:5432/jobwalk',
    'JOBWALK_PUBLIC_URL': 'https://jobwalk.app',
    'JOBWALK_SECRET': 'a-very-long-random-secret-for-signing-things',
    'ANTHROPIC_API_KEY': 'sk-ant-test',
    'EMAIL_PROVIDER': 'resend',
    'RESEND_API_KEY': 're_test',
  };

  List<String> problems(Map<String, String> env) {
    try {
      ServerConfig.fromEnvironment(env);
      return const [];
    } on ConfigError catch (e) {
      return e.problems;
    }
  }

  test('development defaults need only a model choice', () {
    final c = ServerConfig.fromEnvironment({'JOBWALK_FAKE_MODEL': 'true'});
    expect(c.env, 'development');
    expect(c.fakeModel, isTrue);
    expect(c.databaseUrl, contains('localhost'));
    expect(c.publicUrl.toString(), 'http://localhost:8080');
    expect(c.emailProvider, 'log');
    expect(c.storage, 'file');
    expect(c.stripeEnabled, isFalse);
    expect(c.migrateOnStart, isTrue);
    expect(c.runWorker, isTrue);
  });

  test('defaults to Opus 5.5 at high effort', () {
    final c = ServerConfig.fromEnvironment({'ANTHROPIC_API_KEY': 'k'});
    expect(c.drafter.model, 'claude-opus-5-5');
    expect(c.drafter.effort, 'high');
    expect(c.drafter.maxTokens, 32000);
    expect(c.drafter.useFallbacks, isTrue);
    expect(c.anthropicBaseUrl, isNull);
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

  test('a complete production configuration', () {
    final c = ServerConfig.fromEnvironment({
      ...production,
      'STORAGE': 's3',
      'S3_ENDPOINT': 'https://acct.r2.cloudflarestorage.com',
      'S3_BUCKET': 'jobwalk',
      'S3_ACCESS_KEY_ID': 'id',
      'S3_SECRET_ACCESS_KEY': 'secret',
      'STRIPE_SECRET_KEY': 'sk_live_x',
      'STRIPE_WEBHOOK_SECRET': 'whsec_a',
      'STRIPE_CONNECT_WEBHOOK_SECRET': 'whsec_b',
      'STRIPE_PRICE_PRO': 'price_pro',
      'JOBWALK_CORS_ORIGINS': 'https://a.example, https://b.example',
      'JOBWALK_EFFORT': 'medium',
      'PORT': '9000',
    });
    expect(c.isProduction, isTrue);
    expect(c.publicUrl.toString(), 'https://jobwalk.app');
    expect(c.stripeEnabled, isTrue);
    expect(c.stripeWebhookSecrets, ['whsec_a', 'whsec_b']);
    expect(c.corsOrigins, ['https://a.example', 'https://b.example']);
    expect(c.drafter.effort, 'medium');
    expect(c.port, 9000);
    expect(c.warnings, isEmpty);
  });

  test('production refuses unsafe settings, listing every problem', () {
    final found = problems({
      'JOBWALK_ENV': 'production',
      'JOBWALK_FAKE_MODEL': 'true',
      'JOBWALK_PUBLIC_URL': 'http://jobwalk.app',
    });
    expect(found, hasLength(greaterThanOrEqualTo(4)));
    expect(found.join('\n'), contains('DATABASE_URL'));
    expect(found.join('\n'), contains('https'));
    expect(found.join('\n'), contains('JOBWALK_SECRET'));
    expect(found.join('\n'), contains('JOBWALK_FAKE_MODEL'));
    expect(found.join('\n'), contains('EMAIL_PROVIDER=log'));
  });

  test('production warns about single-machine storage and missing billing', () {
    final c = ServerConfig.fromEnvironment(production);
    expect(c.warnings.join('\n'), contains('STORAGE=file'));
    expect(c.warnings.join('\n'), contains('billing'));
  });

  test('validates values', () {
    expect(problems({'JOBWALK_FAKE_MODEL': 'true', 'PORT': 'x'}), isNotEmpty);
    expect(
      problems({'ANTHROPIC_API_KEY': 'k', 'JOBWALK_EFFORT': 'extreme'}),
      isNotEmpty,
    );
    expect(
      problems({'ANTHROPIC_API_KEY': 'k', 'JOBWALK_PUBLIC_URL': 'jobwalk.app'}),
      isNotEmpty,
    );
    expect(
      problems({'ANTHROPIC_API_KEY': 'k', 'JOBWALK_SECRET': 'short'}),
      isNotEmpty,
    );
    expect(
      problems({'ANTHROPIC_API_KEY': 'k', 'STRIPE_SECRET_KEY': 'sk_test_x'}),
      contains(contains('STRIPE_WEBHOOK_SECRET')),
    );
    expect(problems({'ANTHROPIC_API_KEY': 'k', 'STORAGE': 's3'}), hasLength(4));
    expect(
      problems({
        'ANTHROPIC_API_KEY': 'k',
        'JOBWALK_REVIEW_EMAIL': 'review@example.com',
      }),
      isNotEmpty,
    );
    expect(problems({}), contains(contains('ANTHROPIC_API_KEY')));
  });
}
