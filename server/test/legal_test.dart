import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

void main() {
  test('the privacy policy names the AI provider in use', () {
    expect(
      privacyPage(const LegalInfo(aiProvider: 'gemini')),
      contains("We use Google's paid Gemini API"),
    );
    final groq = privacyPage(const LegalInfo(aiProvider: 'groq'));
    expect(groq, contains('to Groq, which runs the model'));
    expect(groq, contains('<b>Groq</b> writes AI drafts'));
    final demo = privacyPage(const LegalInfo(aiProvider: 'demo'));
    expect(demo, contains('writes sample drafts'));
    expect(demo, isNot(contains('Anthropic')));
    expect(demo, isNot(contains('writes AI drafts, as described')));
  });

  test('lists only the services this server uses', () {
    final page = privacyPage(
      const LegalInfo(emailProvider: 'resend', storage: 's3', payments: true),
    );
    expect(page, contains('<b>Resend</b>'));
    expect(page, contains('cloud storage provider'));
    expect(page, contains('<b>Stripe</b>'));
    final bare = privacyPage(const LegalInfo());
    expect(bare, isNot(contains('<b>Resend</b>')));
    expect(bare, isNot(contains('<b>Stripe</b>')));
    expect(bare, contains('Our hosting and database providers'));
  });

  test("says when Gemini's free tier is in use", () {
    final free = privacyPage(
      const LegalInfo(
        aiProvider: 'gemini',
        aiFreeTier: true,
        backupProviders: ['groq'],
      ),
    );
    expect(free, contains("During the beta we use Google's free Gemini API"));
    expect(free, contains('people at Google may review them'));
    expect(free, isNot(contains("Google's paid Gemini API")));
    expect(free, contains("Groq, under Groq's terms for API customers"));
    expect(
      LegalInfo.fromConfig(
        ServerConfig.fromEnvironment({
          'GEMINI_API_KEY': 'g',
          'JOBWALK_AI_PROVIDER': 'gemini',
          'JOBWALK_FREE_TIER': 'true',
        }),
      ).aiFreeTier,
      isTrue,
    );
  });

  test('names a backup AI company, and only another company', () {
    final page = privacyPage(
      const LegalInfo(aiProvider: 'gemini', backupProviders: ['claude']),
    );
    expect(
      page,
      contains(
        'When Google is too busy to take a draft, the same request goes '
        'instead to Anthropic, under its commercial terms',
      ),
    );
    expect(page, contains('<b>Anthropic</b> writes AI drafts when Google'));
    final sameCompany = LegalInfo.fromConfig(
      ServerConfig.fromEnvironment({
        'GEMINI_API_KEY': 'g',
        'JOBWALK_AI_PROVIDER': 'gemini',
      }),
    );
    expect(sameCompany.backupProviders, isEmpty);
    expect(privacyPage(sameCompany), isNot(contains('too busy')));
    final mixed = LegalInfo.fromConfig(
      ServerConfig.fromEnvironment({
        'GEMINI_API_KEY': 'g',
        'ANTHROPIC_API_KEY': 'a',
        'JOBWALK_AI_PROVIDER': 'gemini',
        'JOBWALK_BACKUP_MODELS': 'gemini-3.7-flash,claude-sonnet-5',
      }),
    );
    expect(mixed.backupProviders, ['claude']);
  });

  test('names the database and photo hosts it can tell', () {
    final supabase = privacyPage(
      const LegalInfo(
        storage: 's3',
        databaseProvider: 'Supabase',
        storageProvider: 'Supabase',
      ),
    );
    expect(
      supabase,
      contains('<b>Supabase</b> hosts our database and keeps job photos.'),
    );
    expect(supabase, contains('Our hosting provider runs the servers'));
    final split = privacyPage(
      const LegalInfo(
        storage: 's3',
        databaseProvider: 'Neon',
        storageProvider: 'Cloudflare',
      ),
    );
    expect(split, contains('<b>Neon</b> hosts our database.'));
    expect(split, contains('<b>Cloudflare</b> keeps job photos.'));
    expect(providerFor('aws-0-us-east-1.pooler.supabase.com'), 'Supabase');
    expect(providerFor('abcd.storage.supabase.co'), 'Supabase');
    expect(providerFor('acct.r2.cloudflarestorage.com'), 'Cloudflare');
    expect(providerFor('notsupabase.co'), isNull);
    expect(providerFor('db'), isNull);
  });

  test('the terms carry the operator and its fees', () {
    const info = LegalInfo(
      company: 'Brightline Software LLC',
      contactEmail: 'legal@brightline.test',
      address: '12 Elm St, Austin, TX 78704',
      governingLaw: 'Texas',
      platformFeeBps: 150,
      trialDrafts: 10,
    );
    final terms = termsPage(info);
    expect(terms, contains('the State of Texas, United States'));
    expect(terms, contains('platform fee of\n1.5%'));
    expect(terms, contains('New accounts include 10 free AI drafts'));
    expect(
      terms,
      contains(
        'Brightline Software LLC · 12 Elm St, Austin, TX 78704 · '
        'legal@brightline.test',
      ),
    );
    expect(privacyPage(info), contains('mailto:legal@brightline.test'));
  });

  test('comes from the server config', () {
    final info = LegalInfo.fromConfig(
      ServerConfig.fromEnvironment({
        'JOBWALK_FAKE_MODEL': 'true',
        'JOBWALK_LEGAL_NAME': 'Jobwalk Inc.',
        'JOBWALK_SESSION_DAYS': '30',
      }),
    );
    expect(info.company, 'Jobwalk Inc.');
    expect(info.aiProvider, 'demo');
    expect(info.aiCompany, isNull);
    expect(privacyPage(info), contains('30 days without use'));
  });
}
