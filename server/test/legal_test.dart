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
