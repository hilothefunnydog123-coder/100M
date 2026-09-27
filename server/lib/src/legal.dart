import 'config.dart';
import 'pages.dart';

/// Who runs this server and which services it uses, so the privacy policy
/// and terms describe the deployment they're served from.
class LegalInfo {
  const LegalInfo({
    this.company = 'Jobwalk',
    this.contactEmail = 'hello@jobwalk.app',
    this.address = '',
    this.governingLaw = '',
    this.aiProvider = 'claude',
    this.emailProvider = 'log',
    this.storage = 'file',
    this.payments = false,
    this.platformFeeBps = 100,
    this.processingFeeBps = 290,
    this.processingFeeCents = 30,
    this.trialDrafts = 25,
    this.monthlyDraftCap = 500,
    this.sessionDays = 90,
  });

  factory LegalInfo.fromConfig(ServerConfig c) => LegalInfo(
    company: c.legalName,
    contactEmail: c.contactEmail,
    address: c.legalAddress,
    governingLaw: c.governingLaw,
    aiProvider: c.fakeModel ? 'demo' : c.aiProvider,
    emailProvider: c.emailProvider,
    storage: c.storage,
    payments: c.stripeEnabled,
    platformFeeBps: c.platformFeeBps,
    processingFeeBps: c.processingFeeBps,
    processingFeeCents: c.processingFeeCents,
    trialDrafts: c.trialDrafts,
    monthlyDraftCap: c.monthlyDraftCap,
    sessionDays: c.sessionDays,
  );

  /// Bump when the text below changes.
  static const updated = 'September 27, 2026';

  final String company;
  final String contactEmail;
  final String address;
  final String governingLaw;

  /// `claude`, `gemini`, `groq`, or `demo` (sample drafts, no provider).
  final String aiProvider;
  final String emailProvider;
  final String storage;
  final bool payments;
  final int platformFeeBps;
  final int processingFeeBps;
  final int processingFeeCents;
  final int trialDrafts;
  final int monthlyDraftCap;
  final int sessionDays;

  /// The company that runs the model, or null when drafts are samples.
  String? get aiCompany => switch (aiProvider) {
    'claude' => 'Anthropic',
    'gemini' => 'Google',
    'groq' => 'Groq',
    _ => null,
  };
}

const _legalCss = '''
.bar{background:#121417}
.bar nav{max-width:760px;margin:0 auto;padding:16px 20px;display:flex;align-items:center;gap:10px}
.bar a{color:#fff;font-weight:900;font-size:19px;text-decoration:none;display:flex;align-items:center;gap:10px}
.mark{width:26px;height:26px;border-radius:7px;background:var(--accent);display:grid;place-items:center}
.mark span{width:10px;height:10px;border:3px solid #fff;border-radius:2px;transform:rotate(45deg)}
.legal{max-width:760px;margin:0 auto;padding:36px 20px 64px}
.legal h1{font-size:36px;letter-spacing:-.6px;margin-bottom:8px}
.legal .updated{color:var(--faint);margin:0 0 28px}
.legal h2{font-size:20px;margin:32px 0 10px}
.legal p,.legal li{color:#2b2f36;max-width:68ch}
.legal ul{padding-left:20px}
.legal li{margin-bottom:8px}
.legal footer{margin-top:44px;padding-top:18px;border-top:1px solid var(--line);color:var(--faint);font-size:14px}
''';

String _legalPage({
  required String title,
  required String description,
  required LegalInfo info,
  required String body,
}) => htmlPage(
  title: '$title · Jobwalk',
  description: description,
  index: true,
  css: _legalCss,
  body:
      '''
<header class="bar"><nav><a href="/"><span class="mark"><span></span></span>Jobwalk</a></nav></header>
<main class="legal">
<h1>${esc(title)}</h1>
<p class="updated">Last updated ${LegalInfo.updated}</p>
$body
<footer>${esc(_contactLine(info))} · <a href="/privacy">Privacy</a> · <a href="/terms">Terms</a></footer>
</main>''',
);

String _contactLine(LegalInfo info) => [
  info.company,
  if (info.address.isNotEmpty) info.address,
  info.contactEmail,
].join(' · ');

String _mailto(LegalInfo info) =>
    '<a href="mailto:${esc(info.contactEmail)}">${esc(info.contactEmail)}</a>';

String _percent(int bps) {
  final pct = bps / 100;
  return pct == pct.roundToDouble() ? '${pct.round()}' : '$pct';
}

/// The privacy policy at `/privacy`.
String privacyPage(LegalInfo info) {
  final company = esc(info.company);
  final ai = info.aiCompany;
  // Fixed text, so it goes into the page as is.
  final aiParagraph = switch (info.aiProvider) {
    'claude' =>
      'When you ask for a draft, we send the job photos, your note, and your '
          'business details and rates to Anthropic, which runs the Claude '
          'model that writes it. Anthropic processes them under its '
          "commercial terms, which don't allow it to train its models on "
          'them.',
    'gemini' =>
      'When you ask for a draft, we send the job photos, your note, and your '
          'business details and rates to Google, which runs the Gemini model '
          "that writes it. We use Google's paid Gemini API, whose terms don't "
          'let Google use them to improve its products.',
    'groq' =>
      'When you ask for a draft, we send the job photos, your note, and your '
          'business details and rates to Groq, which runs the model that '
          "writes it, under Groq's terms for API customers.",
    _ =>
      "This server writes sample drafts and doesn't send your photos to an "
          'AI provider.',
  };
  final processors = [
    if (ai != null) '<li><b>$ai</b> writes AI drafts, as described above.</li>',
    if (info.payments)
      '<li><b>Stripe</b> handles subscriptions and card deposits.</li>',
    if (info.emailProvider == 'resend')
      '<li><b>Resend</b> delivers sign-in codes and notification emails.</li>',
    if (info.storage == 's3')
      '<li>A cloud storage provider keeps job photos.</li>',
    '<li>Our hosting and database providers run the servers the service '
        'lives on.</li>',
  ];

  return _legalPage(
    title: 'Privacy policy',
    description: 'What Jobwalk collects, why, and the choices you have.',
    info: info,
    body:
        '''
<p>$company runs Jobwalk, an app that helps contractors write quotes and get
them approved. This policy explains what we collect, why, who helps us
process it, and the choices you have.</p>

<h2>What we collect</h2>
<ul>
<li><b>From contractors and their crews:</b> your email address and name,
your business details (name, phone, email, address, and trades), your rates
and price list, and the quotes you write: job photos, notes, line items, and
prices.</li>
<li><b>About your customers:</b> what you enter for them (name, phone,
email, and job address), and what they do on the quote page: when they open
it, the option they choose, the name they type to approve it, and their note
if they decline. As the approval record, we also keep the time, their IP
address, and their browser.</li>
<li><b>Payments:</b> Stripe handles card and bank details. We receive the
payment status, amounts, and Stripe account and customer ids, never full
card numbers.</li>
<li><b>Beta waitlist:</b> the email, trade, and crew size you give us.</li>
<li><b>Technical:</b> our servers log each request's time, route, status,
and duration, without personal details. The app keeps your sign-in token in
your phone's secure storage. We don't use advertising or analytics
trackers.</li>
</ul>

<h2>How we use it</h2>
<ul>
<li>To run the service: drafting quotes, hosting quote pages, sending
sign-in codes and notifications, syncing quotes across your crew's phones,
and processing subscriptions and deposits.</li>
<li>To keep it safe and working: rate limits, preventing abuse, and fixing
problems.</li>
<li>To make drafts better: we measure how much you change a draft before
you send it.</li>
</ul>
<p>We don't sell your data or your customers' data, and we don't use it for
advertising.</p>

<h2>AI drafts</h2>
<p>$aiParagraph Quotes you write yourself aren't sent to an AI
provider.</p>

<h2>Who else processes it</h2>
<p>We share data only with the providers that run parts of the service for
us, and only for that purpose:</p>
<ul>
${processors.join('\n')}
</ul>
<p>We may also disclose information when the law requires it, or to protect
people or the service. If $company is merged or sold, this policy keeps
applying to the data collected under it.</p>

<h2>Your customers</h2>
<p>Contractors decide what to collect about their customers and are
responsible for having the right to share it with us. We process it on their
behalf. Customers can ask the contractor, or us at ${_mailto(info)}, to see
or delete what's stored about them.</p>

<h2>How long we keep it</h2>
<ul>
<li>Quotes, their photos, and customer responses stay until you delete the
quote or your account. Deleting a quote removes its photos and its customer
page; deleting your business account removes everything in it.</li>
<li>AI draft results are cleared from our records after 7 days. The quote
you save keeps its own copy.</li>
<li>Sign-in codes expire after 10 minutes, and sessions end after
${info.sessionDays} days without use.</li>
<li>Payment event records are kept for 90 days. Stripe keeps its own
records as the law requires.</li>
<li>Database backups are kept for a limited time and then overwritten.</li>
</ul>

<h2>Security</h2>
<p>Connections use HTTPS. Sign-in codes are stored hashed, photos are served
through short-lived links, and only your crew can see your quotes. No system
is perfectly secure; if a breach affects your data, we'll tell you as the
law requires.</p>

<h2>Your choices</h2>
<ul>
<li>See and correct your details in the app, and turn off notification
emails in Settings.</li>
<li>Delete your account in Settings. Account owners who want a copy of
their business's data can email us for it.</li>
<li>Depending on where you live (for example California or the EU), you
may have more rights, such as asking what we hold about you or asking us to
delete it. Email ${_mailto(info)} and we'll answer within 30 days.</li>
</ul>

<h2>Children</h2>
<p>Jobwalk is for businesses and isn't meant for anyone under 16.</p>

<h2>Changes</h2>
<p>If we change this policy in a way that matters, we'll post the new
version here and email account owners before it takes effect.</p>

<h2>Contact</h2>
<p>${esc(_contactLine(info))}</p>''',
  );
}

/// The terms of service at `/terms`.
String termsPage(LegalInfo info) {
  final company = esc(info.company);
  final law = info.governingLaw.isEmpty
      ? 'the laws of the state where $company is organized'
      : 'the laws of the State of ${esc(info.governingLaw)}, United States';
  final processing =
      '${_percent(info.processingFeeBps)}% + ${info.processingFeeCents}¢';

  return _legalPage(
    title: 'Terms of service',
    description: 'The agreement between Jobwalk and the businesses using it.',
    info: info,
    body:
        '''
<p>These terms are an agreement between you (the business using Jobwalk,
and the people you add to your account) and $company. By creating an
account or using Jobwalk, you agree to them.</p>

<h2>The service</h2>
<p>Jobwalk helps you write quotes from job photos, send them as links, and
get them approved and paid. Some features, like AI drafts and card
deposits, depend on providers we work with.</p>

<h2>Your account</h2>
<p>You must be at least 18 and using Jobwalk for a business. You sign in
with a code sent to your email, so keep that email account secure. The
account owner is responsible for the people they add and what they do in
Jobwalk.</p>

<h2>Your content</h2>
<p>You own your quotes, photos, prices, and customer information. You give
us permission to store, process, and show them only to run Jobwalk for you:
for example, to send photos to our AI provider when you ask for a draft,
and to show a quote to the customer you send it to. You're responsible for
having the right to upload photos and your customers' details, and for any
notice or consent the law requires for them.</p>

<h2>AI drafts are a starting point</h2>
<p>Drafts are estimates an AI model makes from photos, and they can be
wrong, including measurements, quantities, scope, and prices. Review every
line before you send a quote. You decide what to quote and are responsible
for the quotes you send; we don't promise that a draft is accurate,
complete, or profitable.</p>

<h2>Quotes, approvals, and signatures</h2>
<p>A quote you send is an offer from your business to your customer. When
they approve it, the agreement is between you and them; $company isn't a
party to it. We keep an approval record (the name they typed, the option,
the time, their IP address, and their browser) and make it available to
you. You're responsible for your quotes and contracts meeting the laws that
apply to your work, such as licensing, required contract terms, and
cancellation rights.</p>

<h2>Plans and billing</h2>
<p>New accounts include ${info.trialDrafts} free AI drafts, and quotes you
write yourself are always free. Paid plans are billed monthly through Stripe
at the price shown when you subscribe, renew automatically, and can be
canceled anytime; cancellation takes effect at the end of the billing
period. We don't refund partial months unless the law requires it. We'll
give at least 30 days' notice before changing a plan's price. Paid plans
include up to ${info.monthlyDraftCap} AI drafts a month for fair use.</p>

<h2>Card deposits</h2>
<p>To take card deposits through Jobwalk, you set up a Stripe account and
agree to Stripe's Connected Account Agreement. Deposits are paid to your
Stripe account. On each deposit, Jobwalk keeps a platform fee of
${_percent(info.platformFeeBps)}% plus card processing of $processing,
which covers what Stripe charges. Refunds, chargebacks, and disputes with
your customers are yours to handle.</p>

<h2>Fair use</h2>
<p>Don't use Jobwalk to break the law, send spam, upload content you don't
have the rights to, or harm anyone. Don't probe, overload, or
reverse-engineer the service, or work around its limits.</p>

<h2>Availability and changes</h2>
<p>We work to keep Jobwalk running, but we can't promise it will always be
available or free of errors. We may change or retire features. If we shut
the service down, we'll give you at least 30 days to get your data.</p>

<h2>Ending your account</h2>
<p>You can delete your account in Settings at any time. We may suspend or
close accounts that break these terms or put others at risk, with notice
when we can.</p>

<h2>Disclaimers</h2>
<p>To the extent the law allows, Jobwalk is provided as is, without
warranties of any kind.</p>

<h2>Limit of liability</h2>
<p>To the extent the law allows, $company isn't liable for indirect or
consequential losses, such as lost profits or lost jobs, and our total
liability for any claim is limited to what you paid us in the 12 months
before it.</p>

<h2>Indemnity</h2>
<p>You'll cover $company against claims that arise from your quotes, your
work, or your content, except where we caused the problem.</p>

<h2>Governing law</h2>
<p>These terms are governed by $law, without regard to conflict-of-law
rules.</p>

<h2>Changes to these terms</h2>
<p>We'll post changes here and email account owners at least 30 days before
a material change takes effect. Using Jobwalk after that means you accept
the new terms.</p>

<h2>Contact</h2>
<p>${esc(_contactLine(info))}</p>''',
  );
}
