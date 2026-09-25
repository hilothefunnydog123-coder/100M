import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_core/photo_pipeline.dart';

import 'drafter.dart';

/// One past job with a known outcome: the photos from the walkthrough and
/// what the contractor actually charged.
class EvalCase {
  const EvalCase({
    required this.id,
    required this.trade,
    required this.photos,
    required this.actualTotalCents,
    this.note = '',
    this.zip = '',
    this.rates,
    this.option = '',
  });

  final String id;
  final Trade trade;

  /// Paths, relative to the manifest.
  final List<String> photos;
  final int actualTotalCents;
  final String note;
  final String zip;

  /// The contractor's rates; defaults for the trade when absent.
  final Rates? rates;

  /// Which option the actual price corresponds to (matched against option
  /// names). Empty compares against the recommended option.
  final String option;

  factory EvalCase.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final photos = json['photos'];
    final total = json['actual_total'];
    if (id is! String || photos is! List || photos.isEmpty || total is! num) {
      throw const FormatException(
        'Each case needs id, photos, and actual_total.',
      );
    }
    return EvalCase(
      id: id,
      trade: Trade.fromId(json['trade']),
      photos: [for (final p in photos) '$p'],
      actualTotalCents: (total * 100).round(),
      note: json['note'] as String? ?? '',
      zip: json['zip'] as String? ?? '',
      rates: json['rates'] == null ? null : Rates.fromJson(json['rates']),
      option: json['option'] as String? ?? '',
    );
  }

  static List<EvalCase> readManifest(File manifest) => [
    for (final line in manifest.readAsLinesSync())
      if (line.trim().isNotEmpty && !line.trimLeft().startsWith('//'))
        EvalCase.fromJson(jsonDecode(line) as Map<String, Object?>),
  ];
}

class EvalResult {
  const EvalResult({
    required this.id,
    required this.trade,
    required this.actualTotalCents,
    this.predictedTotalCents,
    this.option = '',
    this.usable = false,
    this.error,
    this.costUsd,
    this.latencyMs = 0,
    this.lines = 0,
  });

  final String id;
  final Trade trade;
  final int actualTotalCents;
  final int? predictedTotalCents;
  final String option;
  final bool usable;
  final String? error;
  final double? costUsd;
  final int latencyMs;
  final int lines;

  /// Signed error in percent: positive means the draft was high.
  double? get errorPct {
    final p = predictedTotalCents;
    if (p == null || actualTotalCents == 0) return null;
    return (p - actualTotalCents) / actualTotalCents * 100;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'trade': trade.id,
    'actual_total': actualTotalCents / 100,
    'predicted_total': predictedTotalCents == null
        ? null
        : predictedTotalCents! / 100,
    'error_pct': errorPct,
    'option': option,
    'usable': usable,
    'error': error,
    'cost_usd': costUsd,
    'latency_ms': latencyMs,
    'lines': lines,
  };
}

/// Drafts one case the way production would and prices it with the case's
/// rates.
Future<EvalResult> runCase(
  EvalCase c,
  QuoteDrafter drafter, {
  required Directory root,
}) async {
  final watch = Stopwatch()..start();
  try {
    final photos = [
      for (final path in c.photos)
        () {
          final prepared = preparePhoto(
            File('${root.path}/$path').readAsBytesSync(),
          );
          return JobPhoto(bytes: prepared.jpeg, mediaType: 'image/jpeg');
        }(),
    ];
    final rates = c.rates ?? Rates.forTrade(c.trade);
    final draft = await drafter.draft(
      DraftRequest(
        profile: BusinessProfile(
          name: 'Eval Contractor',
          trades: [c.trade],
          zip: c.zip,
        ),
        rates: rates,
        photos: photos,
        note: c.note,
      ),
    );
    if (!draft.draft.isUsable) {
      return EvalResult(
        id: c.id,
        trade: c.trade,
        actualTotalCents: c.actualTotalCents,
        costUsd: draft.stats.estimatedCostUsd,
        latencyMs: watch.elapsedMilliseconds,
      );
    }
    final quote = QuoteBuilder.fromDraft(
      draft.draft,
      id: c.id,
      number: 1,
      rates: rates,
      now: DateTime.now().toUtc(),
    );
    final tier = _matchTier(quote, c.option);
    return EvalResult(
      id: c.id,
      trade: c.trade,
      actualTotalCents: c.actualTotalCents,
      predictedTotalCents: quote.totals(tier?.id).totalCents,
      option: tier?.name ?? '',
      usable: true,
      costUsd: draft.stats.estimatedCostUsd,
      latencyMs: watch.elapsedMilliseconds,
      lines: quote.totals(tier?.id).lineCount,
    );
  } on Object catch (e) {
    return EvalResult(
      id: c.id,
      trade: c.trade,
      actualTotalCents: c.actualTotalCents,
      error: '$e',
      latencyMs: watch.elapsedMilliseconds,
    );
  }
}

Tier? _matchTier(Quote quote, String option) {
  if (quote.tiers.isEmpty) return null;
  final wanted = option.trim().toLowerCase();
  if (wanted.isNotEmpty) {
    for (final t in quote.tiers) {
      if (t.name.toLowerCase().contains(wanted) || t.id == wanted) return t;
    }
  }
  return quote.tier(quote.defaultTierId);
}

/// Headline accuracy numbers for a run.
class EvalSummary {
  EvalSummary(this.results);

  final List<EvalResult> results;

  List<double> get _errors => [for (final r in results) ?r.errorPct];

  int get cases => results.length;
  int get priced => _errors.length;
  int get failed => results.where((r) => r.error != null).length;
  int get unusable => results.where((r) => r.error == null && !r.usable).length;

  /// Median absolute percent error of the total.
  double? get medianAbsErrorPct => _median([for (final e in _errors) e.abs()]);

  /// Median signed error: positive means drafts run high.
  double? get medianBiasPct => _median(_errors);

  double? withinPct(double band) => priced == 0
      ? null
      : _errors.where((e) => e.abs() <= band).length / priced * 100;

  double? get meanCostUsd {
    final costs = [for (final r in results) ?r.costUsd];
    return costs.isEmpty ? null : costs.reduce((a, b) => a + b) / costs.length;
  }

  int? latencyPercentile(double p) {
    final ms = [for (final r in results) r.latencyMs]..sort();
    if (ms.isEmpty) return null;
    return ms[math.min(ms.length - 1, (p * ms.length).floor())];
  }

  Map<String, Object?> toJson() => {
    'cases': cases,
    'priced': priced,
    'failed': failed,
    'unusable': unusable,
    'median_abs_error_pct': medianAbsErrorPct,
    'median_bias_pct': medianBiasPct,
    'within_10_pct': withinPct(10),
    'within_20_pct': withinPct(20),
    'mean_cost_usd': meanCostUsd,
    'latency_p50_ms': latencyPercentile(0.5),
    'latency_p90_ms': latencyPercentile(0.9),
    'by_trade': {
      for (final t in {for (final r in results) r.trade})
        t.id: EvalSummary(
          results.where((r) => r.trade == t).toList(),
        )._headline(),
    },
  };

  Map<String, Object?> _headline() => {
    'cases': cases,
    'median_abs_error_pct': medianAbsErrorPct,
    'within_20_pct': withinPct(20),
  };

  String toMarkdown() {
    String pct(double? v) => v == null ? 'n/a' : '${v.toStringAsFixed(1)}%';
    final b = StringBuffer()
      ..writeln('| Metric | Value |')
      ..writeln('|---|---|')
      ..writeln(
        '| Cases | $cases ($priced priced, $unusable unusable, '
        '$failed failed) |',
      )
      ..writeln('| Median abs. error of total | ${pct(medianAbsErrorPct)} |')
      ..writeln('| Median bias (+ is high) | ${pct(medianBiasPct)} |')
      ..writeln('| Within 10% | ${pct(withinPct(10))} |')
      ..writeln('| Within 20% | ${pct(withinPct(20))} |')
      ..writeln(
        '| Mean cost per draft | '
        '${meanCostUsd == null ? 'n/a' : '\$${meanCostUsd!.toStringAsFixed(3)}'} |',
      )
      ..writeln(
        '| Latency p50 / p90 | ${latencyPercentile(0.5) ?? 0} ms / '
        '${latencyPercentile(0.9) ?? 0} ms |',
      );
    return b.toString();
  }
}

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  final s = [...values]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}
