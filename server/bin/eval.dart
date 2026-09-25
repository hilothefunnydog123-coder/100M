import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:jobwalk_server/jobwalk_server.dart';

/// Scores AI drafts against what contractors actually charged.
///
///   dart run bin/eval.dart --manifest ../eval/jobs.jsonl --out ../eval/out
///
/// See eval/README.md for the manifest format.
Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('manifest', mandatory: true, help: 'JSONL of past jobs.')
    ..addOption('out', defaultsTo: 'eval-out', help: 'Output directory.')
    ..addOption('limit', help: 'Only the first N cases.')
    ..addOption('concurrency', defaultsTo: '4')
    ..addOption('model', defaultsTo: 'claude-opus-5-5')
    ..addOption('effort', defaultsTo: 'high')
    ..addOption('max-cost', help: 'Stop starting new cases above this USD.')
    ..addFlag('fake', help: 'Use sample drafts instead of Claude.')
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
  final concurrency = int.tryParse(args.option('concurrency')!) ?? 4;
  final maxCost = double.tryParse(args.option('max-cost') ?? '');

  final QuoteDrafter drafter;
  if (args.flag('fake')) {
    drafter = DemoDrafter(delay: Duration.zero);
  } else {
    final key = Platform.environment['ANTHROPIC_API_KEY'];
    if (key == null || key.isEmpty) {
      stderr.writeln('Set ANTHROPIC_API_KEY, or pass --fake.');
      exitCode = 64;
      return;
    }
    final base = Platform.environment['ANTHROPIC_BASE_URL'];
    drafter = Drafter(
      api: ClaudeClient(
        apiKey: key,
        baseUrl: base == null || base.isEmpty ? null : Uri.parse(base),
      ),
      config: DrafterConfig(
        model: args.option('model')!,
        effort: args.option('effort')!,
      ),
    );
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
      final e = r.errorPct;
      stdout.writeln(
        '${c.id}: ${r.error ?? (e == null ? 'unusable' : '${e >= 0 ? '+' : ''}${e.toStringAsFixed(1)}%')}',
      );
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  results.sort((a, b) => a.id.compareTo(b.id));

  final out = Directory(args.option('out')!)..createSync(recursive: true);
  final summary = EvalSummary(results);
  File('${out.path}/results.jsonl').writeAsStringSync(
    '${results.map((r) => jsonEncode(r.toJson())).join('\n')}\n',
  );
  File('${out.path}/summary.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'prompt_version': promptVersion,
      'model': args.flag('fake') ? 'demo' : args.option('model'),
      'effort': args.option('effort'),
      ...summary.toJson(),
    }),
  );
  File('${out.path}/summary.md').writeAsStringSync(summary.toMarkdown());
  stdout.writeln('\n${summary.toMarkdown()}');
}
