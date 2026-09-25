/// Build-time configuration, set with `--dart-define`:
///
///   flutter run --dart-define=API_BASE_URL=https://api.jobwalk.app
///
/// Without an API base URL the app runs in demo mode: sample drafts, and
/// quote links that live only on this device.
class AppConfig {
  const AppConfig({
    this.apiBaseUrl,
    this.demoMode = true,
    this.privacyPolicyUrl = 'https://jobwalk.app/privacy',
    this.termsUrl = 'https://jobwalk.app/terms',
  });

  final Uri? apiBaseUrl;

  /// Sample drafts, no network. Always on when no API URL is configured.
  final bool demoMode;

  final String privacyPolicyUrl;
  final String termsUrl;

  factory AppConfig.fromEnvironment() {
    const base = String.fromEnvironment('API_BASE_URL');
    const demo = bool.fromEnvironment('DEMO_MODE');
    return AppConfig(
      apiBaseUrl: base.isEmpty ? null : Uri.parse(base),
      demoMode: demo || base.isEmpty,
    );
  }
}
