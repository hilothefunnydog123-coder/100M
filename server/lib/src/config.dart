import 'analyzer.dart';

/// Server configuration, read from environment variables.
///
/// App settings are namespaced `SPOTCHECK_*` on purpose: generic names such
/// as `CLAUDE_EFFORT` are set by other tools (Claude Code sets it for its own
/// sessions) and would silently change cost and latency here.
class ServerConfig {
  const ServerConfig({
    required this.analyzer,
    this.apiKey,
    this.apiBaseUrl,
    this.port = 8080,
    this.fakeModel = false,
    this.corsOrigins = const ['*'],
    this.installBurst = 6,
    this.installRefill = const Duration(minutes: 10),
    this.ipBurst = 30,
    this.ipRefill = const Duration(minutes: 2),
    this.maxConcurrent = 16,
    this.maxQueued = 64,
  });

  final AnalyzerConfig analyzer;
  final String? apiKey;

  /// Honors `ANTHROPIC_BASE_URL`, like the official SDKs.
  final Uri? apiBaseUrl;

  final int port;

  /// Serve canned assessments without calling Claude (local development).
  final bool fakeModel;

  final List<String> corsOrigins;
  final int installBurst;
  final Duration installRefill;
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

    final fake = boolVar('SPOTCHECK_FAKE_MODEL', false);
    final apiKey = env['ANTHROPIC_API_KEY'];
    if (!fake && (apiKey == null || apiKey.isEmpty)) {
      throw StateError(
        'ANTHROPIC_API_KEY is not set. Set it, or set '
        'SPOTCHECK_FAKE_MODEL=true for canned local responses.',
      );
    }
    const effortLevels = {'low', 'medium', 'high', 'xhigh', 'max'};
    final effort = env['SPOTCHECK_EFFORT'] ?? 'high';
    if (!effortLevels.contains(effort)) {
      throw StateError('SPOTCHECK_EFFORT must be one of $effortLevels.');
    }

    final baseUrl = env['ANTHROPIC_BASE_URL'];
    return ServerConfig(
      apiKey: apiKey,
      apiBaseUrl: baseUrl == null || baseUrl.isEmpty
          ? null
          : Uri.parse(baseUrl),
      fakeModel: fake,
      port: intVar('PORT', 8080),
      corsOrigins: (env['SPOTCHECK_CORS_ORIGINS'] ?? '*')
          .split(',')
          .map((o) => o.trim())
          .where((o) => o.isNotEmpty)
          .toList(),
      analyzer: AnalyzerConfig(
        model: env['SPOTCHECK_MODEL'] ?? 'claude-opus-5-5',
        effort: effort,
        maxTokens: intVar('SPOTCHECK_MAX_TOKENS', 16000),
        useFallbacks: boolVar('SPOTCHECK_FALLBACKS', true),
        ensembleSize: intVar('SPOTCHECK_ENSEMBLE_SIZE', 1).clamp(1, 5),
      ),
      installBurst: intVar('SPOTCHECK_RATE_LIMIT_INSTALL_BURST', 6),
      installRefill: Duration(
        minutes: intVar('SPOTCHECK_RATE_LIMIT_INSTALL_REFILL_MINUTES', 10),
      ),
      ipBurst: intVar('SPOTCHECK_RATE_LIMIT_IP_BURST', 30),
      ipRefill: Duration(
        minutes: intVar('SPOTCHECK_RATE_LIMIT_IP_REFILL_MINUTES', 2),
      ),
      maxConcurrent: intVar('SPOTCHECK_MAX_CONCURRENT', 16),
      maxQueued: intVar('SPOTCHECK_MAX_QUEUED', 64),
    );
  }
}
