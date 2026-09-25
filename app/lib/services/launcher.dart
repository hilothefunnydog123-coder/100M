import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the messages app with [body] ready to send.
Future<bool> composeText(String phone, String body) {
  final to = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  return launchUrl(Uri.parse('sms:$to?body=${Uri.encodeComponent(body)}'));
}

Future<bool> composeEmail(String to, String subject, String body) => launchUrl(
  Uri.parse(
    'mailto:${Uri.encodeComponent(to)}'
    '?subject=${Uri.encodeComponent(subject)}'
    '&body=${Uri.encodeComponent(body)}',
  ),
);

Future<bool> callNumber(String phone) => launchUrl(
  Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), '')),
);

Future<bool> openLink(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

Future<void> copyText(String text) =>
    Clipboard.setData(ClipboardData(text: text));

Future<void> shareText(String text, {String? subject}) async {
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
}
