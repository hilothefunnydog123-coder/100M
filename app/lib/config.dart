/// Build-time configuration, set with `--dart-define`:
///
///   flutter run --dart-define=API_BASE_URL=https://api.example.com
///
/// Without an API base URL the app runs in demo mode with canned results.
class AppConfig {
  const AppConfig({
    this.apiBaseUrl,
    this.demoMode = true,
    this.freeChecks = 3,
    this.privacyPolicyUrl = 'https://spotcheck.example/privacy',
    this.termsUrl = 'https://spotcheck.example/terms',
  });

  final Uri? apiBaseUrl;

  /// Canned results, no network. Always on when no API URL is configured.
  final bool demoMode;

  /// Checks included before the paywall.
  final int freeChecks;

  final String privacyPolicyUrl;
  final String termsUrl;

  factory AppConfig.fromEnvironment() {
    const base = String.fromEnvironment('API_BASE_URL');
    const demo = bool.fromEnvironment('DEMO_MODE');
    const free = int.fromEnvironment('FREE_CHECKS', defaultValue: 3);
    return AppConfig(
      apiBaseUrl: base.isEmpty ? null : Uri.parse(base),
      demoMode: demo || base.isEmpty,
      freeChecks: free,
    );
  }
}
