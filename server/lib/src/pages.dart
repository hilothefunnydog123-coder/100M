import 'dart:convert';

import 'package:jobwalk_core/jobwalk_core.dart';

import 'services/quotes.dart';

const _escape = HtmlEscape();

/// Escapes text for HTML element content and attribute values.
String esc(String s) => _escape.convert(s);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Sep 25, 2026" (UTC; the customer's time zone isn't known).
String formatDay(DateTime d) {
  final u = d.toUtc();
  return '${_months[u.month - 1]} ${u.day}, ${u.year}';
}

const _baseCss = '''
:root{--ink:#16181c;--muted:#5d636d;--faint:#8b919b;--line:#e6e2da;
--paper:#f6f4ef;--card:#fff;--accent:#f2541b;--accent-ink:#b53a0c;
--ok:#16704a;--ok-bg:#e8f5ee;--warn:#8a4b00;--warn-bg:#fff3e0}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--paper);color:var(--ink);
font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
a{color:inherit}
h1,h2,h3{line-height:1.15;margin:0}
.num{font-variant-numeric:tabular-nums}
.btn{display:inline-block;border:0;border-radius:12px;background:var(--ink);
color:#fff;font:inherit;font-weight:700;padding:14px 20px;text-decoration:none;
cursor:pointer;text-align:center}
.btn:hover{opacity:.92}
.btn.accent{background:var(--accent)}
.btn.block{display:block;width:100%}
.btn.ghost{background:transparent;color:var(--ink);box-shadow:inset 0 0 0 1.5px var(--line)}
input[type=text],input[type=email],select,textarea{width:100%;font:inherit;
padding:12px 14px;border:1.5px solid var(--line);border-radius:12px;
background:#fff;color:var(--ink)}
input:focus,select:focus,textarea:focus,.btn:focus-visible,summary:focus-visible{
outline:3px solid var(--accent);outline-offset:2px}
''';

String _page({
  required String title,
  required String body,
  String css = '',
  String description = '',
  bool index = false,
}) =>
    '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title>
${description.isEmpty ? '' : '<meta name="description" content="${esc(description)}">\n<meta property="og:title" content="${esc(title)}">\n<meta property="og:description" content="${esc(description)}">'}
${index ? '' : '<meta name="robots" content="noindex">'}
<style>$_baseCss$css</style>
</head>
<body>
$body
</body>
</html>
''';

/// A plain page for errors and confirmations.
String messagePage(String title, String message, {String? homeHref}) => _page(
  title: title,
  css: '''
.msg{max-width:520px;margin:12vh auto;padding:0 20px;text-align:center}
.msg h1{font-size:28px;margin-bottom:12px}.msg p{color:var(--muted)}''',
  body:
      '''
<main class="msg">
<h1>${esc(title)}</h1>
<p>${esc(message)}</p>
${homeHref == null ? '' : '<p><a href="${esc(homeHref)}">Jobwalk</a></p>'}
</main>''',
);

// ---------------------------------------------------------------------------
// Customer quote page
// ---------------------------------------------------------------------------

const _quoteCss = '''
.wrap{max-width:760px;margin:0 auto;padding:16px}
.doc{background:var(--card);border-radius:20px;padding:28px 22px;
box-shadow:0 1px 2px rgba(0,0,0,.05),0 8px 30px rgba(0,0,0,.05)}
@media(min-width:600px){.doc{padding:40px 44px}.wrap{padding:32px 20px}}
.biz h1{font-size:26px;letter-spacing:-.3px}
.contact{color:var(--muted);font-size:15px;margin-top:6px;display:flex;flex-wrap:wrap;gap:4px 14px}
.contact a{text-decoration:none;border-bottom:1px solid var(--line)}
.meta{display:grid;grid-template-columns:1fr auto;gap:4px 16px;margin:24px 0;padding:16px 0;
border-top:1px solid var(--line);border-bottom:1px solid var(--line);font-size:15px}
.meta .k{color:var(--faint);font-size:12px;font-weight:700;letter-spacing:.06em;text-transform:uppercase}
.meta .r{text-align:right}
.title{font-size:24px;letter-spacing:-.2px;margin-bottom:8px}
.summary{color:var(--muted);margin:0 0 24px}
.banner{border-radius:14px;padding:14px 16px;margin:0 0 20px;background:var(--paper);font-weight:600}
.banner.ok{background:var(--ok-bg);color:var(--ok)}
.banner.warn{background:var(--warn-bg);color:var(--warn)}
.banner .btn{margin-top:12px}
.label{font-size:12px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:var(--faint);margin:28px 0 10px}
.radio{position:absolute;opacity:0;pointer-events:none}
.options{display:grid;gap:10px}
.option{display:grid;grid-template-columns:22px 1fr auto;gap:12px;align-items:start;
border:1.5px solid var(--line);border-radius:14px;padding:14px 16px;cursor:pointer}
.option .dot{width:20px;height:20px;border-radius:50%;border:2px solid var(--faint);margin-top:2px}
.option .name{font-weight:700}
.option .blurb{color:var(--muted);font-size:14px;margin-top:2px}
.option .price{font-weight:800;font-size:18px}
.rec{display:inline-block;margin-left:6px;font-size:11px;font-weight:800;letter-spacing:.06em;
text-transform:uppercase;color:var(--accent-ink);background:#ffeee6;border-radius:6px;padding:2px 6px;vertical-align:2px}
.detail{display:none}
.single .detail{display:block}
.section{font-size:12px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:var(--faint);
padding:18px 0 6px;border-bottom:1px solid var(--line)}
.line{display:grid;grid-template-columns:1fr auto;gap:16px;padding:12px 0;border-bottom:1px solid var(--line)}
.line .d{font-weight:600}
.line .sub{color:var(--muted);font-size:14px}
.line .amt{font-weight:700;text-align:right;white-space:nowrap}
.totals{margin-top:12px}
.totals .row{display:flex;justify-content:space-between;padding:4px 0;color:var(--muted)}
.totals .row.total{color:var(--ink);font-weight:800;font-size:22px;padding-top:10px}
.totals .row.deposit{color:var(--ink);font-weight:600}
ul.plain{margin:0;padding-left:20px;color:var(--muted)}
.note{background:var(--paper);border-radius:14px;padding:16px 18px;margin:0}
.terms{color:var(--muted);font-size:14px}
.approve{margin-top:32px;padding-top:24px;border-top:2px solid var(--ink)}
.approve label.f{display:block;font-weight:700;margin:0 0 6px}
.agree{display:flex;gap:10px;align-items:flex-start;margin:14px 0 18px;color:var(--muted);font-size:15px}
.agree input{width:20px;height:20px;margin-top:2px;flex:none}
.approve .btn{display:none;width:100%}
.single .approve .btn{display:block}
details.decline{margin-top:18px;color:var(--muted)}
details.decline summary{cursor:pointer;font-weight:600}
details.decline form{margin-top:12px;display:grid;gap:10px}
.foot{text-align:center;color:var(--faint);font-size:13px;margin:22px 0 40px}
.paid{margin-top:10px;font-weight:700}
.foot a{color:var(--muted)}
@media print{body{background:#fff}.wrap{padding:0}.doc{box-shadow:none;padding:0}
.approve,details.decline,.foot,.banner .btn{display:none}}
''';

/// The page a customer opens from the texted link.
String quotePage(
  CustomerView view, {
  required DateTime now,
  required String homeHref,
  String? flash,
  String? error,
  bool sample = false,
}) {
  final q = view.quote;
  final r = view.response;
  final approved = r.approvedAt != null;
  final expired = !approved && now.isAfter(q.validUntil);
  final canApprove = !approved && !expired && !sample;
  final chosen = approved
      ? (q.option(r.approvedTierId) ?? q.defaultOption)
      : q.defaultOption;
  // Once approved, only the approved option is shown.
  final options = approved ? [chosen] : q.options;
  final single = options.length == 1;

  final b = StringBuffer();
  final css = StringBuffer(_quoteCss);
  for (var i = 0; i < options.length; i++) {
    css.write(
      '#o$i:checked~.options label[for=o$i]{border-color:var(--ink);'
      'box-shadow:0 0 0 1px var(--ink)}'
      '#o$i:checked~.options label[for=o$i] .dot{border-color:var(--ink);'
      'background:var(--ink);box-shadow:inset 0 0 0 3px #fff}'
      '#o$i:checked~.details .d$i{display:block}'
      '#o$i:checked~.approve .b$i{display:block}',
    );
  }

  b.writeln('<div class="wrap"><main class="doc">');
  b.writeln(_businessHeader(q.business));

  b.writeln('<div class="meta">');
  b.writeln(
    '<div><div class="k">Quote</div><div class="num">#${q.number}</div></div>'
    '<div class="r"><div class="k">Date</div><div>${formatDay(q.issuedAt)}</div></div>',
  );
  final who = [
    if (q.customerName.isNotEmpty) q.customerName,
    if (q.customerAddress.isNotEmpty) q.customerAddress,
  ].join(', ');
  b.writeln(
    '<div><div class="k">For</div><div>${who.isEmpty ? '&nbsp;' : esc(who)}</div></div>'
    '<div class="r"><div class="k">Valid until</div><div>${formatDay(q.validUntil)}</div></div>',
  );
  b.writeln('</div>');

  // Status banners.
  if (sample) {
    b.writeln(
      '<div class="banner">This is a sample quote. Contractors send quotes '
      'like this from the Jobwalk app.</div>',
    );
  }
  if (approved) {
    b.writeln(
      '<div class="banner ok">Approved ${formatDay(r.approvedAt!)}'
      '${r.signature.isEmpty ? '' : ' by ${esc(r.signature)}'}: '
      '${esc(chosen.name)}, ${Money.format(chosen.totalCents)}. '
      '${esc(q.business.name)} will be in touch to schedule the work.',
    );
    final paidAt = view.depositPaidAt;
    if (paidAt != null) {
      b.writeln(
        '<div class="paid">Deposit of '
        '${Money.format(view.depositPaidCents ?? chosen.depositCents)} paid '
        '${formatDay(paidAt)}. Thank you!</div>',
      );
    } else if (flash == 'deposit') {
      b.writeln(
        '<div class="paid">Thanks! Your payment is processing. You\'ll get a '
        'receipt by email.</div>',
      );
    } else if (view.canPayDeposit) {
      b.writeln(
        '<form method="post" action="${esc('/q/${view.publicId}/deposit')}">'
        '<button class="btn accent block" type="submit">Pay the '
        '${Money.format(chosen.depositCents)} deposit by card</button></form>',
      );
    } else if (q.business.paymentLink.isNotEmpty && chosen.depositCents > 0) {
      b.writeln(
        '<a class="btn accent block" href="${esc(q.business.paymentLink)}" '
        'target="_blank" rel="noopener noreferrer">Pay the '
        '${Money.format(chosen.depositCents)} deposit</a>',
      );
    }
    b.writeln('</div>');
  } else if (expired) {
    b.writeln(
      '<div class="banner warn">This quote expired on '
      '${formatDay(q.validUntil)}. Contact ${esc(q.business.name)} for an '
      'updated one.</div>',
    );
  } else if (r.declinedAt != null) {
    b.writeln(
      '<div class="banner">${flash == 'declined' ? 'Thanks for letting us know. ' : ''}'
      'You declined this quote on ${formatDay(r.declinedAt!)}. Changed your '
      'mind? You can still approve it below.</div>',
    );
  }
  if (error != null) {
    b.writeln('<div class="banner warn" role="alert">${esc(error)}</div>');
  }

  if (q.title.isNotEmpty) b.writeln('<h2 class="title">${esc(q.title)}</h2>');
  if (q.summary.isNotEmpty) {
    b.writeln('<p class="summary">${esc(q.summary)}</p>');
  }

  b.writeln(
    canApprove
        ? '<form method="post" action="${esc('/q/${view.publicId}/approve')}" '
              'class="${single ? 'single' : ''}" id="approve">'
        : '<div class="${single ? 'single' : ''}">',
  );
  for (var i = 0; i < options.length; i++) {
    final o = options[i];
    b.writeln(
      '<input class="radio" type="radio" name="option" id="o$i" '
      'value="${esc(o.id)}"${identical(o, chosen) ? ' checked' : ''}>',
    );
  }
  if (!single) {
    b.writeln('<div class="label">Choose an option</div>');
  }
  b.writeln('<div class="options">');
  if (!single) {
    for (var i = 0; i < options.length; i++) {
      final o = options[i];
      b.writeln(
        '<label class="option" for="o$i"><span class="dot"></span>'
        '<span><span class="name">${esc(o.name)}</span>'
        '${o.recommended ? '<span class="rec">Recommended</span>' : ''}'
        '${o.summary.isEmpty ? '' : '<div class="blurb">${esc(o.summary)}</div>'}'
        '</span><span class="price num">${Money.format(o.totalCents)}</span></label>',
      );
    }
  }
  b.writeln('</div>');

  b.writeln('<div class="details">');
  for (var i = 0; i < options.length; i++) {
    b.writeln(
      _optionDetail(options[i], i, depositPct: q.depositPct, single: single),
    );
  }
  b.writeln('</div>');

  if (q.exclusions.isNotEmpty) {
    b.writeln('<div class="label">Not included</div><ul class="plain">');
    for (final e in q.exclusions) {
      b.writeln('<li>${esc(e)}</li>');
    }
    b.writeln('</ul>');
  }
  if (q.message.isNotEmpty) {
    b.writeln(
      '<div class="label">From ${esc(q.business.name)}</div>'
      '<p class="note">${esc(q.message)}</p>',
    );
  }
  if (q.terms.isNotEmpty) {
    b.writeln(
      '<div class="label">Terms</div><p class="terms">${esc(q.terms)}</p>',
    );
  }

  if (canApprove) {
    b.writeln('<div class="approve">');
    b.writeln(
      '<label class="f" for="name">Your name</label>'
      '<input type="text" id="name" name="name" maxlength="80" '
      'autocomplete="name" required value="${esc(q.customerName)}">'
      '<label class="agree"><input type="checkbox" name="agree" value="yes" '
      'required><span>I approve this quote and its terms'
      '${q.depositPct > 0 ? ', and I understand a deposit is due to schedule the work' : ''}.</span></label>',
    );
    for (var i = 0; i < options.length; i++) {
      final o = options[i];
      b.writeln(
        '<button class="btn accent b$i" type="submit">Approve'
        '${single ? '' : ' ${esc(o.name)}'}: ${Money.format(o.totalCents)}</button>',
      );
    }
    b.writeln('</div></form>');
    b.writeln(
      '<details class="decline"><summary>Not ready to approve?</summary>'
      '<form method="post" action="${esc('/q/${view.publicId}/decline')}">'
      '<label for="reason">Anything ${esc(q.business.name)} should know? '
      '(optional)</label>'
      '<textarea id="reason" name="reason" rows="3" maxlength="500"></textarea>'
      '<button class="btn ghost" type="submit">Decline this quote</button>'
      '</form></details>',
    );
  } else {
    b.writeln('</div>');
  }

  b.writeln('</main>');
  b.writeln(
    '<p class="foot">Sent with <a href="${esc(homeHref)}">Jobwalk</a>, '
    'the fastest way for crews to quote.</p></div>',
  );

  final optionsLine = q.options.length == 1
      ? Money.format(q.options.single.totalCents)
      : '${q.options.length} options from '
            '${Money.format(q.options.map((o) => o.totalCents).reduce((a, b) => a < b ? a : b))}';
  return _page(
    title: 'Quote #${q.number} from ${q.business.name}',
    description: [if (q.title.isNotEmpty) q.title, optionsLine].join(' · '),
    css: css.toString(),
    body: b.toString(),
  );
}

String _businessHeader(PublicBusiness biz) {
  final contact = [
    if (biz.phone.isNotEmpty)
      '<a href="tel:${esc(biz.phone.replaceAll(RegExp(r'[^0-9+]'), ''))}">${esc(biz.phone)}</a>',
    if (biz.email.isNotEmpty)
      '<a href="mailto:${esc(biz.email)}">${esc(biz.email)}</a>',
    if (biz.license.isNotEmpty) '<span>License ${esc(biz.license)}</span>',
  ];
  return '<header class="biz"><h1>${esc(biz.name)}</h1>'
      '${contact.isEmpty ? '' : '<div class="contact">${contact.join()}</div>'}'
      '</header>';
}

String _optionDetail(
  PublicOption o,
  int index, {
  required double depositPct,
  required bool single,
}) {
  final b = StringBuffer('<section class="detail d$index">');
  if (!single) {
    b.write('<div class="label">What\'s in ${esc(o.name)}</div>');
  }
  String? section;
  for (final l in o.lines) {
    if (l.section.isNotEmpty && l.section != section) {
      section = l.section;
      b.write('<div class="section">${esc(section)}</div>');
    }
    final quantity = describeQuantity(l.quantity, l.unit);
    final sub = [
      if (l.detail.isNotEmpty) esc(l.detail),
      if (quantity.isNotEmpty) esc(quantity),
    ].join(' · ');
    b.write(
      '<div class="line"><div><div class="d">${esc(l.description)}</div>'
      '${sub.isEmpty ? '' : '<div class="sub">$sub</div>'}</div>'
      '<div class="amt num">${Money.format(l.totalCents)}</div></div>',
    );
  }
  String row(String label, int cents, [String cls = '']) =>
      '<div class="row $cls"><span>${esc(label)}</span>'
      '<span class="num">${Money.format(cents)}</span></div>';
  b.write('<div class="totals">');
  final hasAdjustments =
      o.minimumAdjustmentCents > 0 || o.discountCents > 0 || o.taxCents > 0;
  if (hasAdjustments) b.write(row('Subtotal', o.subtotalCents));
  if (o.minimumAdjustmentCents > 0) {
    b.write(row('Minimum job charge', o.minimumAdjustmentCents));
  }
  if (o.discountCents > 0) {
    b.write(
      '<div class="row"><span>Discount</span><span class="num">'
      '-${Money.format(o.discountCents)}</span></div>',
    );
  }
  if (o.taxCents > 0) {
    final rate = o.taxRatePct == o.taxRatePct.roundToDouble()
        ? '${o.taxRatePct.round()}'
        : '${o.taxRatePct}';
    b.write(row('Tax ($rate%)', o.taxCents));
  }
  b.write(row('Total', o.totalCents, 'total'));
  if (o.depositCents > 0) {
    final pct = depositPct == depositPct.roundToDouble()
        ? '${depositPct.round()}'
        : '$depositPct';
    b.write(row('Deposit due at approval ($pct%)', o.depositCents, 'deposit'));
  }
  b.write('</div></section>');
  return b.toString();
}

// ---------------------------------------------------------------------------
// Landing page
// ---------------------------------------------------------------------------

const _landingCss = '''
.top{background:#121417;color:#fff}
.nav{max-width:1080px;margin:0 auto;padding:18px 20px;display:flex;justify-content:space-between;align-items:center}
.logo{font-weight:900;font-size:20px;letter-spacing:-.4px;display:flex;align-items:center;gap:10px;text-decoration:none}
.mark{width:28px;height:28px;border-radius:8px;background:var(--accent);display:grid;place-items:center}
.mark span{width:12px;height:12px;border:3px solid #fff;border-radius:3px;transform:rotate(45deg)}
.nav a.btn{padding:10px 16px}
.hero{max-width:1080px;margin:0 auto;padding:40px 20px 64px;display:grid;gap:40px;align-items:center}
@media(min-width:880px){.hero{grid-template-columns:1.1fr .9fr;padding:72px 20px 96px}}
.eyebrow{color:#ffb08f;font-weight:700;font-size:14px;letter-spacing:.08em;text-transform:uppercase}
.hero h1{font-size:44px;letter-spacing:-1.2px;margin:14px 0 18px}
@media(min-width:880px){.hero h1{font-size:60px}}
.hero p{color:#c9ccd2;font-size:19px;max-width:560px;margin:0 0 28px}
.cta{display:flex;flex-wrap:wrap;gap:12px}
.cta .ghost{color:#fff;box-shadow:inset 0 0 0 1.5px #3a3f47}
.phone{background:#fff;color:var(--ink);border-radius:32px;padding:14px;max-width:360px;margin:0 auto;
box-shadow:0 30px 80px rgba(0,0,0,.45);border:8px solid #2a2e35}
.screen{background:var(--paper);border-radius:20px;padding:18px}
.screen .biz{font-weight:800}
.screen .muted{color:var(--muted);font-size:13px}
.pill{display:flex;justify-content:space-between;align-items:center;background:#fff;border:1.5px solid var(--line);
border-radius:12px;padding:10px 12px;margin-top:8px;font-size:14px}
.pill.on{border-color:var(--ink);box-shadow:0 0 0 1px var(--ink)}
.pill b{font-size:16px}
.mini{margin-top:12px;font-size:13px}
.mini div{display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid var(--line)}
.approvebar{margin-top:14px;background:var(--accent);color:#fff;font-weight:800;text-align:center;border-radius:12px;padding:12px}
.band{max-width:1080px;margin:0 auto;padding:72px 20px}
.band h2{font-size:34px;letter-spacing:-.6px;margin-bottom:28px}
.steps{display:grid;gap:18px}
@media(min-width:800px){.steps{grid-template-columns:repeat(3,1fr)}}
.card{background:#fff;border-radius:18px;padding:22px;border:1px solid var(--line)}
.card .n{width:34px;height:34px;border-radius:10px;background:var(--ink);color:#fff;display:grid;place-items:center;font-weight:800;margin-bottom:14px}
.card h3{font-size:19px;margin-bottom:8px}
.card p{color:var(--muted);margin:0}
.why{display:grid;gap:18px}
@media(min-width:800px){.why{grid-template-columns:repeat(2,1fr)}}
.price{background:#121417;color:#fff;border-radius:24px;padding:32px;display:grid;gap:24px}
@media(min-width:800px){.price{grid-template-columns:1fr 1fr;align-items:center;padding:44px}}
.price .big{font-size:52px;font-weight:900;letter-spacing:-1.5px}
.price p{color:#c9ccd2}
form.join{display:grid;gap:12px;background:#fff;color:var(--ink);border-radius:18px;padding:22px}
form.join label{font-weight:700;font-size:14px}
.faq details{background:#fff;border:1px solid var(--line);border-radius:14px;padding:16px 18px;margin-bottom:10px}
.faq summary{cursor:pointer;font-weight:700}
.faq p{color:var(--muted);margin:10px 0 0}
.ok{background:var(--ok-bg);color:var(--ok);border-radius:12px;padding:12px 14px;font-weight:700}
footer{color:var(--faint);text-align:center;padding:30px 20px 50px;font-size:14px}
''';

/// The marketing page at `/`.
String landingPage({bool joined = false, String? error}) {
  final tradeOptions = [
    for (final t in Trade.values)
      '<option value="${esc(t.id)}">${esc(t.label)}</option>',
  ].join();
  return _page(
    title: 'Jobwalk: quote the job before you leave the driveway',
    description:
        'Snap a few photos and Jobwalk writes an itemized quote with your '
        'prices. Text it to the customer; they approve from their phone.',
    index: true,
    css: _landingCss,
    body:
        '''
<div class="top">
<nav class="nav"><a class="logo" href="/"><span class="mark"><span></span></span>Jobwalk</a>
<a class="btn accent" href="#join">Join the beta</a></nav>
<section class="hero">
<div>
<div class="eyebrow">Quoting for small crews</div>
<h1>Quote the job before you leave the driveway.</h1>
<p>Take a few photos on the walkthrough. Jobwalk measures the job, writes an
itemized quote with your prices, and gives you a link to text the customer.
They pick an option and approve it from their phone.</p>
<div class="cta"><a class="btn accent" href="#join">Join the beta</a>
<a class="btn ghost" href="/sample">See a sample quote</a></div>
</div>
<div class="phone" aria-hidden="true"><div class="screen">
<div class="biz">Brightline Painting</div>
<div class="muted">Quote #1042 · Living room repaint</div>
<div class="pill"><span>Walls only</span><b>\$725</b></div>
<div class="pill on"><span>Walls + trim</span><b>\$1,245</b></div>
<div class="pill"><span>Full room</span><b>\$1,410</b></div>
<div class="mini">
<div><span>Prep and protection</span><span>\$275</span></div>
<div><span>Walls, 2 coats, premium</span><span>\$495</span></div>
<div><span>Baseboards and casing</span><span>\$340</span></div>
<div><span>Door and frame</span><span>\$90</span></div>
<div><span>Cleanup</span><span>\$45</span></div>
</div>
<div class="approvebar">Approve: \$1,245</div>
</div></div>
</section>
</div>

<section class="band">
<h2>How it works</h2>
<div class="steps">
<div class="card"><div class="n">1</div><h3>Walk the job</h3>
<p>Take 3 to 8 photos and add anything the photos don't show, like "two
coats, ceilings too." Talk-to-text works fine.</p></div>
<div class="card"><div class="n">2</div><h3>Check the draft</h3>
<p>About a minute later you have an itemized quote priced with your labor
rate and markup, plus a short list of assumptions to confirm.</p></div>
<div class="card"><div class="n">3</div><h3>Text it, get approved</h3>
<p>Your customer gets a clean quote page, picks an option, signs, and pays
the deposit with your payment link.</p></div>
</div>
</section>

<section class="band" style="padding-top:0">
<h2>Built for how crews actually sell</h2>
<div class="why">
<div class="card"><h3>Be first</h3><p>Homeowners tend to hire whoever gets
back to them first. Send yours while the other bids are still in someone's
truck.</p></div>
<div class="card"><h3>Your prices, not ours</h3><p>Jobwalk estimates the
work (measurements, hours, materials) and prices it with your rate, your
markup, and your price list. You see how it got every number.</p></div>
<div class="card"><h3>It learns how you price</h3><p>Change a price once
and Jobwalk remembers it for the next job, so drafts get closer to what you
would have written.</p></div>
<div class="card"><h3>Options sell up</h3><p>Good, better, and best options
let customers choose up instead of shopping around.</p></div>
</div>
</section>

<section class="band" id="join" style="padding-top:0">
<div class="price">
<div>
<div class="eyebrow">Pricing</div>
<div class="big">Free in beta</div>
<p>Then \$79 a month per company with unlimited quotes. Crews who join the
beta lock in \$49 a month for as long as they stay.</p>
</div>
<form class="join" method="post" action="/waitlist">
${joined ? '<div class="ok" role="status">You\'re on the list. We\'ll text or email you when your invite is ready.</div>' : ''}
${error == null ? '' : '<div class="ok" style="background:var(--warn-bg);color:var(--warn)" role="alert">${esc(error)}</div>'}
<label for="email">Email</label>
<input type="email" id="email" name="email" required maxlength="120" autocomplete="email" placeholder="you@yourcompany.com">
<label for="trade">What do you do?</label>
<select id="trade" name="trade">$tradeOptions</select>
<label for="crew">Crew size</label>
<select id="crew" name="crew"><option value="solo">Just me</option>
<option value="2-5">2 to 5</option><option value="6-10">6 to 10</option>
<option value="11+">11 or more</option></select>
<button class="btn accent" type="submit">Join the beta</button>
</form>
</div>
</section>

<section class="band faq" style="padding-top:0">
<h2>Questions</h2>
<details><summary>How accurate are the quotes?</summary><p>Jobwalk measures
from things of known size in your photos, like doors, fence sections, and
garage doors, and shows how it got every number. It flags the assumptions
that move the price so you can confirm them before sending. Nothing goes to
a customer until you approve it.</p></details>
<details><summary>What trades does it work for?</summary><p>Painting,
fencing, pressure washing, landscaping, decks, gutters, drywall, flooring,
handyman work, and more. If you quote from a walkthrough, it fits.</p></details>
<details><summary>Do my customers need an app?</summary><p>No. They get a
link by text or email that opens in any browser.</p></details>
<details><summary>How do deposits work?</summary><p>Add your Stripe,
Square, or PayPal payment link, and customers see a button to pay the
deposit right after they approve.</p></details>
</section>
<footer>© 2026 Jobwalk</footer>
''',
  );
}
