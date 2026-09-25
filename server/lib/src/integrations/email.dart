import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class OutgoingEmail {
  const OutgoingEmail({
    required this.to,
    required this.subject,
    required this.text,
    this.html,
  });

  final String to;
  final String subject;
  final String text;
  final String? html;

  Map<String, Object?> toJson() => {
    'to': to,
    'subject': subject,
    'text': text,
    'html': html,
  };

  factory OutgoingEmail.fromJson(Map<String, Object?> json) => OutgoingEmail(
    to: json['to']! as String,
    subject: json['subject']! as String,
    text: json['text']! as String,
    html: json['html'] as String?,
  );
}

class EmailException implements Exception {
  EmailException(this.message, {this.retryable = true});

  final String message;
  final bool retryable;

  @override
  String toString() => 'EmailException: $message';
}

abstract interface class EmailSender {
  Future<void> send(OutgoingEmail email);
}

/// Development: prints emails (sign-in codes included) to the log.
class LogEmailSender implements EmailSender {
  LogEmailSender([void Function(String)? write])
    : _write = write ?? stdout.writeln;

  final void Function(String) _write;

  @override
  Future<void> send(OutgoingEmail email) async => _write(
    jsonEncode({
      'event': 'email_logged',
      'to': email.to,
      'subject': email.subject,
      'text': email.text,
    }),
  );
}

class MemoryEmailSender implements EmailSender {
  final sent = <OutgoingEmail>[];

  /// Fails the next sends when set, to exercise retries.
  EmailException? failWith;

  @override
  Future<void> send(OutgoingEmail email) async {
    final error = failWith;
    if (error != null) throw error;
    sent.add(email);
  }
}

/// Sends through Resend (resend.com): one JSON POST per email.
class ResendEmailSender implements EmailSender {
  ResendEmailSender({
    required this.apiKey,
    required this.from,
    this.replyTo,
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String apiKey;

  /// e.g. `Jobwalk <quotes@jobwalk.app>` on a verified domain.
  final String from;
  final String? replyTo;
  final http.Client _http;

  @override
  Future<void> send(OutgoingEmail email) async {
    final http.Response r;
    try {
      r = await _http
          .post(
            Uri.parse('https://api.resend.com/emails'),
            headers: {
              'authorization': 'Bearer $apiKey',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'from': from,
              'to': [email.to],
              'subject': email.subject,
              'text': email.text,
              'html': ?email.html,
              'reply_to': ?replyTo,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw EmailException('Email provider timed out.');
    } on http.ClientException catch (e) {
      throw EmailException('Email provider unreachable: ${e.message}');
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    throw EmailException(
      'Email provider returned ${r.statusCode}.',
      retryable: r.statusCode == 429 || r.statusCode >= 500,
    );
  }
}

const _text = HtmlEscape(HtmlEscapeMode.element);
const _attr = HtmlEscape(HtmlEscapeMode.attribute);

/// The emails Jobwalk sends. Plain text first; the HTML version is the same
/// words in a simple, readable layout.
class EmailTemplates {
  const EmailTemplates({required this.appUrl});

  /// Where "open the app" links point, e.g. the landing page.
  final String appUrl;

  OutgoingEmail signInCode(String to, String code) => _build(
    to: to,
    subject: 'Your Jobwalk code: $code',
    lines: [
      'Your sign-in code is $code.',
      'It expires in 10 minutes. If you didn\'t ask for it, you can ignore '
          'this email.',
    ],
  );

  OutgoingEmail quoteEvent(
    String to, {
    required String kind,
    required String quoteLabel,
    required String customer,
    required String url,
    String detail = '',
  }) {
    final who = customer.isEmpty ? 'Your customer' : customer;
    final (subject, first) = switch (kind) {
      'viewed' => ('$who opened $quoteLabel', '$who just opened $quoteLabel.'),
      'approved' => (
        '$who approved $quoteLabel',
        '$who approved $quoteLabel. $detail',
      ),
      'declined' => (
        '$who declined $quoteLabel',
        '$who declined $quoteLabel. $detail',
      ),
      'deposit_paid' => (
        'Deposit received for $quoteLabel',
        '$who paid the deposit on $quoteLabel. $detail',
      ),
      'follow_up' => (
        'No decision yet on $quoteLabel',
        '$who hasn\'t approved $quoteLabel yet. $detail',
      ),
      _ => throw ArgumentError.value(kind, 'kind'),
    };
    return _build(
      to: to,
      subject: subject,
      lines: [first.trim(), 'Customer page: $url'],
      button: ('Open Jobwalk', appUrl),
    );
  }

  OutgoingEmail memberAdded(String to, {required String business}) => _build(
    to: to,
    subject: 'You were added to $business on Jobwalk',
    lines: [
      'You now have access to $business\'s quotes on Jobwalk.',
      'Open the app and sign in with this email address.',
    ],
    button: ('Get Jobwalk', appUrl),
  );

  OutgoingEmail _build({
    required String to,
    required String subject,
    required List<String> lines,
    (String, String)? button,
  }) {
    final text = [
      ...lines,
      if (button != null) '${button.$1}: ${button.$2}',
    ].join('\n\n');
    final html = StringBuffer()
      ..write(
        '<div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,'
        'Arial,sans-serif;font-size:16px;line-height:1.5;color:#16181c;'
        'max-width:520px;margin:0 auto;padding:24px">',
      );
    for (final line in lines) {
      html.write('<p style="margin:0 0 16px">${_text.convert(line)}</p>');
    }
    if (button != null) {
      html.write(
        '<p style="margin:24px 0"><a href="${_attr.convert(button.$2)}" '
        'style="background:#f2541b;color:#fff;text-decoration:none;'
        'font-weight:700;padding:12px 20px;border-radius:10px;'
        'display:inline-block">${_text.convert(button.$1)}</a></p>',
      );
    }
    html.write(
      '<p style="margin:24px 0 0;color:#8a9099;font-size:13px">Jobwalk</p>'
      '</div>',
    );
    return OutgoingEmail(
      to: to,
      subject: subject,
      text: text,
      html: html.toString(),
    );
  }
}
