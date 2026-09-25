import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:spotcheck_core/photo_pipeline.dart';
import 'package:spotcheck_core/spotcheck_core.dart';
import 'package:spotcheck_server/eval.dart';
import 'package:spotcheck_server/spotcheck_server.dart';

/// Runs the analyzer over a labeled manifest and reports accuracy, safety,
/// fairness, cost, and latency. Every real run spends API credits: start
/// with --limit and watch the cost line.
///
///   dart run bin/eval.dart --manifest ../eval/data/scin/manifest.jsonl \
///       --limit 25 --concurrency 4
Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('manifest', mandatory: true, help: 'JSONL manifest of cases')
    ..addOption('out', help: 'Output directory (default: eval/out/<time>)')
    ..addOption('limit', help: 'Only run the first N cases')
    ..addOption('concurrency', defaultsTo: '4')
    ..addOption('model', defaultsTo: 'claude-opus-5-5')
    ..addOption('effort', defaultsTo: 'high')
    ..addOption('ensemble', defaultsTo: '1')
    ..addOption(
      'max-cost',
      defaultsTo: '25',
      help: 'Stop starting new cases once estimated spend passes this (USD)',
    )
    ..addOption('cache', defaultsTo: '../eval/data/cache')
    ..addFlag('fake', help: 'Use the demo analyzer (no API calls)')
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln(parser.usage);
    exit(64);
  }
  if (args.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final manifest = File(args.option('manifest')!);
  var cases = loadManifest(manifest);
  final limit = int.tryParse(args.option('limit') ?? '');
  if (limit != null) cases = cases.take(limit).toList();
  final concurrency = int.parse(args.option('concurrency')!);
  final maxCost = double.parse(args.option('max-cost')!);
  final fake = args.flag('fake');
  final config = AnalyzerConfig(
    model: args.option('model')!,
    effort: args.option('effort')!,
    ensembleSize: int.parse(args.option('ensemble')!),
  );

  final CheckAnalyzer analyzer;
  http.Client? apiHttp;
  if (fake) {
    analyzer = DemoAnalyzer(delay: Duration.zero);
  } else {
    final key = Platform.environment['ANTHROPIC_API_KEY'];
    if (key == null || key.isEmpty) {
      stderr.writeln('Set ANTHROPIC_API_KEY, or pass --fake.');
      exit(78);
    }
    apiHttp = http.Client();
    analyzer = Analyzer(
      api: ClaudeClient(apiKey: key, httpClient: apiHttp),
      config: config,
    );
  }

  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
  final outDir = Directory(args.option('out') ?? '../eval/out/$stamp')
    ..createSync(recursive: true);
  final images = _ImageCache(Directory(args.option('cache')!), manifest.parent);
  final runConfig = {
    'manifest': manifest.path,
    'model': fake ? 'demo' : config.model,
    'effort': config.effort,
    'ensemble': config.ensembleSize,
    'prompt_version': promptVersion,
  };

  stdout.writeln(
    'Running ${cases.length} cases with ${runConfig['model']} '
    '(effort ${config.effort}, ensemble ${config.ensembleSize}), '
    'concurrency $concurrency, max spend \$$maxCost.',
  );

  final outcomes = <CaseOutcome>[];
  final matcher = LabelMatcher();
  final resultsSink = File('${outDir.path}/results.jsonl').openWrite();
  var spent = 0.0;
  var next = 0;
  var stopped = false;

  Future<void> worker() async {
    while (next < cases.length && !stopped) {
      if (spent >= maxCost) {
        stopped = true;
        stdout.writeln('Stopping: estimated spend reached \$$maxCost.');
        break;
      }
      final c = cases[next++];
      final outcome = await _runCase(c, analyzer, images);
      spent += outcome.costUsd ?? 0;
      outcomes.add(outcome);
      resultsSink.writeln(jsonEncode(outcome.toJson(matcher)));
      final s = CaseScore.of(outcome, matcher);
      stdout.writeln(
        '[${outcomes.length}/${cases.length}] ${c.id}: '
        '${outcome.result?.status.id ?? 'error'} '
        'urgency=${outcome.result?.urgency?.id ?? '-'} '
        'top3=${s.top3 ?? '-'} '
        '${outcome.error == null ? '' : 'error="${outcome.error}" '}'
        '(\$${(outcome.costUsd ?? 0).toStringAsFixed(3)}, '
        '${(outcome.latency.inMilliseconds / 1000).toStringAsFixed(1)}s)',
      );
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  await resultsSink.close();
  apiHttp?.close();

  final summary = EvalSummary(outcomes, matcher, config: runConfig);
  File('${outDir.path}/summary.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(summary.toJson()),
  );
  final report = summary.toMarkdown();
  File('${outDir.path}/report.md').writeAsStringSync(report);
  stdout
    ..writeln()
    ..writeln(report)
    ..writeln('Wrote ${outDir.path}/{results.jsonl,summary.json,report.md}');
}

Future<CaseOutcome> _runCase(
  EvalCase c,
  CheckAnalyzer analyzer,
  _ImageCache images,
) async {
  final watch = Stopwatch()..start();
  try {
    final photos = <CheckPhoto>[];
    for (final image in c.images) {
      // The same preparation the app applies before upload.
      final prepared = preparePhoto(await images.load(image));
      photos.add(
        CheckPhoto(
          bytes: prepared.jpeg,
          mediaType: 'image/jpeg',
          kind: image.kind,
        ),
      );
    }
    final analysis = await analyzer.analyze(
      CheckRequest(
        site: c.site,
        answers: c.answers,
        photos: photos,
        note: c.note,
      ),
      id: c.id,
      userId: 'eval',
    );
    return CaseOutcome(
      evalCase: c,
      result: analysis.result,
      costUsd: analysis.stats.estimatedCostUsd,
      latency: analysis.stats.latency,
    );
  } on Object catch (e) {
    return CaseOutcome(evalCase: c, error: '$e', latency: watch.elapsed);
  }
}

/// Loads images from local paths or URLs, caching downloads on disk.
class _ImageCache {
  _ImageCache(this.dir, this.manifestDir);

  final Directory dir;
  final Directory manifestDir;
  final _http = http.Client();

  Future<Uint8List> _download(Uri uri) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final r = await _http.get(uri).timeout(const Duration(seconds: 60));
        if (r.statusCode == 200) return r.bodyBytes;
        if (attempt >= 2) throw HttpException('HTTP ${r.statusCode}', uri: uri);
      } on TimeoutException {
        if (attempt >= 2) rethrow;
      }
      await Future<void>.delayed(Duration(seconds: 1 << attempt));
    }
  }

  Future<Uint8List> _cached(Uri uri) async {
    final name = uri.pathSegments.isEmpty
        ? uri.toString().hashCode.toString()
        : uri.pathSegments.last;
    final file = File('${dir.path}/$name');
    if (file.existsSync()) return file.readAsBytesSync();
    final bytes = await _download(uri);
    dir.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return bytes;
  }

  Future<Uint8List> load(EvalImage image) async {
    if (image.url != null) return _cached(Uri.parse(image.url!));
    if (image.path != null) {
      return File('${manifestDir.path}/${image.path}').readAsBytesSync();
    }
    throw const FormatException('Image has neither url nor path.');
  }
}
