import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_server/jobwalk_server.dart';

/// Scores AI drafts against what contractors actually charged.
///
///   dart run bin/eval.dart --manifest ../eval/jobs.jsonl --out ../eval/out
///   dart run bin/eval.dart --manifest ../eval/samples.jsonl --provider gemini
///
/// See eval/README.md for the manifest format.
Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('manifest', mandatory: true, help: 'JSONL of past jobs.')
    ..addOption('out', defaultsTo: 'eval-out', help: 'Output directory.')
    ..addOption('limit', help: 'Only the first N cases.')
    ..addOption(
      'provider',
      allowed: ['claude', 'groq', 'gemini'],
      defaultsTo: 'claude',
    )
    ..addOption(
      'model',
      help:
          'Default: claude-opus-5-5, ${GroqDrafterConfig.defaultModel} on '
          'Groq, ${GeminiDrafterConfig.defaultModel} on Gemini.',
    )
    ..addOption('effort', help: 'Default: high, or medium on Groq.')
    ..addOption('max-tokens', help: 'Output budget: reasoning plus answer.')
    ..addFlag(
      'free-tier',
      negatable: false,
      help: "Fit Groq's free tier: one photo per job, light reasoning.",
    )
    ..addOption(
      'concurrency',
      help: 'Drafts at a time. Default: 4, or 1 on Groq and Gemini.',
    )
    ..addOption('max-cost', help: 'Stop starting new cases above this USD.')
    ..addFlag('fake', help: 'Use sample drafts instead of a model.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    exitCode = 64;
    return;
  }
  if (args.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final manifest = File(args.option('manifest')!);
  var cases = EvalCase.readManifest(manifest);
  final limit = int.tryParse(args.option('limit') ?? '');
  if (limit != null) cases = cases.take(limit).toList();
  final groq = args.option('provider') == 'groq';
  final gemini = args.option('provider') == 'gemini';
  final concurrency =
      int.tryParse(args.option('concurrency') ?? '') ??
      (groq || gemini ? 1 : 4);
  final maxCost = double.tryParse(args.option('max-cost') ?? '');
  final maxTokens = int.tryParse(args.option('max-tokens') ?? '');

  String? env(String name) {
    final v = Platform.environment[name]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  void fail(String message) {
    stderr.writeln(message);
    exitCode = 64;
  }

  if (args.flag('free-tier') && !groq) {
    return fail('--free-tier goes with --provider groq.');
  }
  final QuoteDrafter drafter;
  final String model;
  final String effort;
  if (args.flag('fake')) {
    drafter = DemoDrafter(delay: Duration.zero);
    model = 'demo';
    effort = '';
  } else if (groq) {
    final key = env('GROQ_API_KEY');
    if (key == null) return fail('Set GROQ_API_KEY, or pass --fake.');
    final preset = args.flag('free-tier')
        ? GroqDrafterConfig.freeTier
        : const GroqDrafterConfig();
    final config = preset.copyWith(
      model: args.option('model'),
      effort: args.option('effort'),
      maxTokens: maxTokens,
    );
    if (!GroqDrafterConfig.efforts.contains(config.effort)) {
      return fail(
        '--effort must be one of ${GroqDrafterConfig.efforts.join(', ')} '
        'on Groq.',
      );
    }
    final base = env('GROQ_BASE_URL');
    drafter = GroqDrafter(
      api: GroqClient(
        apiKey: key,
        baseUrl: base == null ? null : Uri.parse(base),
        // Wait out per-minute rate limits instead of failing cases.
        maxRetries: 6,
      ),
      config: config,
    );
    model = config.model;
    effort = config.effort;
  } else if (gemini) {
    final key = env('GEMINI_API_KEY') ?? env('GOOGLE_API_KEY');
    if (key == null) return fail('Set GEMINI_API_KEY, or pass --fake.');
    final config = const GeminiDrafterConfig().copyWith(
      model: args.option('model'),
      effort: args.option('effort'),
      maxTokens: maxTokens,
    );
    if (!GeminiDrafterConfig.efforts.contains(config.effort)) {
      return fail(
        '--effort must be one of ${GeminiDrafterConfig.efforts.join(', ')} '
        'on Gemini.',
      );
    }
    final base = env('GEMINI_BASE_URL');
    drafter = GeminiDrafter(
      api: GeminiClient(
        apiKey: key,
        baseUrl: base == null ? null : Uri.parse(base),
        // Wait out per-minute rate limits instead of failing cases.
        maxRetries: 6,
      ),
      config: config,
    );
    model = config.model;
    effort = config.effort;
  } else {
    final key = env('ANTHROPIC_API_KEY');
    if (key == null) return fail('Set ANTHROPIC_API_KEY, or pass --fake.');
    final config = DrafterConfig(
      model: args.option('model') ?? 'claude-opus-5-5',
      effort: args.option('effort') ?? 'high',
      maxTokens: maxTokens ?? 32000,
    );
    if (!DrafterConfig.efforts.contains(config.effort)) {
      return fail(
        '--effort must be one of ${DrafterConfig.efforts.join(', ')}.',
      );
    }
    final base = env('ANTHROPIC_BASE_URL');
    drafter = Drafter(
      api: ClaudeClient(
        apiKey: key,
        baseUrl: base == null ? null : Uri.parse(base),
      ),
      config: config,
    );
    model = config.model;
    effort = config.effort;
  }

  final results = <EvalResult>[];
  var spent = 0.0;
  var next = 0;
  Future<void> worker() async {
    while (next < cases.length) {
      if (maxCost != null && spent >= maxCost) return;
      final c = cases[next++];
      final r = await runCase(c, drafter, root: manifest.parent);
      spent += r.costUsd ?? 0;
      results.add(r);
      stdout.writeln('${c.id}: ${_describe(r)}');
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  results.sort((a, b) => a.id.compareTo(b.id));

  final out = Directory(args.option('out')!)..createSync(recursive: true);
  final summary = EvalSummary(results);
  File('${out.path}/results.jsonl').writeAsStringSync(
    '${results.map((r) => jsonEncode(r.toJson())).join('\n')}\n',
  );
  final drafts = Directory('${out.path}/drafts')..createSync();
  for (final r in results) {
    if (r.draft case final draft?) {
      final name = r.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      File(
        '${drafts.path}/$name.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(draft));
    }
  }
  File('${out.path}/summary.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'prompt_version': promptVersion,
      'provider': args.flag('fake') ? 'demo' : args.option('provider'),
      'model': model,
      'effort': effort,
      if (args.flag('free-tier')) 'free_tier': true,
      ...summary.toJson(),
    }),
  );
  File('${out.path}/summary.md').writeAsStringSync(summary.toMarkdown());
  stdout.writeln('\n${summary.toMarkdown()}');
}

/// One line per case, e.g. `fence: +4.2%: $4,850.00 vs $4,655.00 (9 lines,
/// 41.5 h)`, or just the draft's total when the actual price is unknown.
String _describe(EvalResult r) {
  if (r.error case final error?) return 'failed: $error';
  final predicted = r.predictedTotalCents;
  if (!r.usable || predicted == null) return 'unusable (asked for retakes)';
  final total = Money.format(predicted, cents: true);
  final size = '${r.lines} lines, ${r.laborHours.toStringAsFixed(1)} h';
  final e = r.errorPct;
  if (e == null) return '$total ($size)';
  final actual = Money.format(r.actualTotalCents!, cents: true);
  return '${e >= 0 ? '+' : ''}${e.toStringAsFixed(1)}%: $total vs $actual '
      '($size)';
}
