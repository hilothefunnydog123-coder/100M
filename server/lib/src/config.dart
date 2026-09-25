import 'drafter.dart';

/// Server configuration, read from environment variables.
///
/// Settings are namespaced `JOBWALK_*` on purpose: generic names such as
/// `CLAUDE_EFFORT` are set by other tools and would silently change cost
/// and latency here.
class ServerConfig {
  const ServerConfig({
    required this.drafter,
    this.apiKey,
    this.apiBaseUrl,
    this.port = 8080,
    this.fakeModel = false,
    this.dataDir = 'data',
    this.publicBaseUrl,
    this.corsOrigins = const ['*'],
    this.installBurst = 10,
    this.installRefill = const Duration(minutes: 3),
    this.ipBurst = 60,
    this.ipRefill = const Duration(seconds: 10),
    this.maxConcurrent = 16,
    this.maxQueued = 64,
  });

  final DrafterConfig drafter;
  final String? apiKey;

  /// Honors `ANTHROPIC_BASE_URL`, like the official SDKs.
  final Uri? apiBaseUrl;

  final int port;

  /// Serve canned sample drafts without calling Claude (local development).
  final bool fakeModel;

  /// Where published quotes and waitlist signups are stored.
  final String dataDir;

  /// Origin used in quote links, e.g. `https://jobwalk.app`. Defaults to the
  /// origin of each request.
  final Uri? publicBaseUrl;

  final List<String> corsOrigins;

  /// Drafts per install: burst, then one more per [installRefill].
  final int installBurst;
  final Duration installRefill;

  /// Writes (drafts, publishes, approvals, signups) per IP address.
  final int ipBurst;
  final Duration ipRefill;
  final int maxConcurrent;
  final int maxQueued;

  factory ServerConfig.fromEnvironment(Map<String, String> env) {
    int intVar(String name, int fallback) =>
        int.tryParse(env[name] ?? '') ?? fallback;
    bool boolVar(String name, bool fallback) =>
        switch (env[name]?.toLowerCase()) {
          'true' || '1' || 'yes' => true,
          'false' || '0' || 'no' => false,
          _ => fallback,
        };
    Uri? urlVar(String name) {
      final value = env[name];
      if (value == null || value.isEmpty) return null;
      final uri = Uri.tryParse(value);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        throw StateError('$name must be an absolute URL.');
      }
      return uri;
    }

    final fake = boolVar('JOBWALK_FAKE_MODEL', false);
    final apiKey = env['ANTHROPIC_API_KEY'];
    if (!fake && (apiKey == null || apiKey.isEmpty)) {
      throw StateError(
        'ANTHROPIC_API_KEY is not set. Set it, or set '
        'JOBWALK_FAKE_MODEL=true for canned sample drafts.',
      );
    }
    const effortLevels = {'low', 'medium', 'high', 'xhigh', 'max'};
    final effort = env['JOBWALK_EFFORT'] ?? 'high';
    if (!effortLevels.contains(effort)) {
      throw StateError('JOBWALK_EFFORT must be one of $effortLevels.');
    }

    return ServerConfig(
      apiKey: apiKey,
      apiBaseUrl: urlVar('ANTHROPIC_BASE_URL'),
      fakeModel: fake,
      port: intVar('PORT', 8080),
      dataDir: env['JOBWALK_DATA_DIR'] ?? 'data',
      publicBaseUrl: urlVar('JOBWALK_PUBLIC_URL'),
      corsOrigins: (env['JOBWALK_CORS_ORIGINS'] ?? '*')
          .split(',')
          .map((o) => o.trim())
          .where((o) => o.isNotEmpty)
          .toList(),
      drafter: DrafterConfig(
        model: env['JOBWALK_MODEL'] ?? 'claude-opus-5-5',
        effort: effort,
        maxTokens: intVar('JOBWALK_MAX_TOKENS', 32000),
        useFallbacks: boolVar('JOBWALK_FALLBACKS', true),
      ),
      installBurst: intVar('JOBWALK_RATE_LIMIT_INSTALL_BURST', 10),
      installRefill: Duration(
        seconds: intVar('JOBWALK_RATE_LIMIT_INSTALL_REFILL_SECONDS', 180),
      ),
      ipBurst: intVar('JOBWALK_RATE_LIMIT_IP_BURST', 60),
      ipRefill: Duration(
        seconds: intVar('JOBWALK_RATE_LIMIT_IP_REFILL_SECONDS', 10),
      ),
      maxConcurrent: intVar('JOBWALK_MAX_CONCURRENT', 16),
      maxQueued: intVar('JOBWALK_MAX_QUEUED', 64),
    );
  }
}
