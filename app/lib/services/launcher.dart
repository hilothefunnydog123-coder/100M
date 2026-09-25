import 'package:share_plus/share_plus.dart';
import 'package:spotcheck_core/spotcheck_core.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> callNumber(String number) =>
    launchUrl(Uri(scheme: 'tel', path: number));

/// Opens a map search for the right kind of care nearby.
Future<bool> findCareNearby(CareSetting setting) {
  final query = switch (setting) {
    CareSetting.emergencyRoom => 'emergency room',
    CareSetting.urgentCare => 'urgent care',
    CareSetting.dermatologist => 'dermatologist',
    CareSetting.eyeDoctor => 'eye doctor',
    CareSetting.dentist => 'dentist',
    CareSetting.pharmacist || CareSetting.selfCare => 'pharmacy',
    CareSetting.primaryCare => 'primary care doctor',
  };
  return launchUrl(
    Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': query}),
    mode: LaunchMode.externalApplication,
  );
}

Future<bool> openLink(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

Future<void> shareText(String text, {String? subject}) async {
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
}
