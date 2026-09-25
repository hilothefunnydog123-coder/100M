import 'dart:math' as math;

import 'package:spotcheck_core/spotcheck_core.dart';

import 'eval_case.dart';
import 'label_matcher.dart';

/// The outcome of running one case.
class CaseOutcome {
  CaseOutcome({
    required this.evalCase,
    this.result,
    this.error,
    this.costUsd,
    this.latency = Duration.zero,
  });

  final EvalCase evalCase;
  final CheckResult? result;
  final String? error;
  final double? costUsd;
  final Duration latency;

  bool get completed => result?.status == CheckStatus.complete;

  List<Possibility> get predictions =>
      result?.assessment?.possibilities ?? const [];

  Map<String, Object?> toJson(LabelMatcher matcher) {
    final s = CaseScore.of(this, matcher);
    return {
      'id': evalCase.id,
      'site': evalCase.site.id,
      'fitzpatrick': evalCase.fitzpatrick,
      'labels': [
        for (final l in evalCase.labels) {'name': l.name, 'weight': l.weight},
      ],
      'serious': evalCase.serious,
      'min_urgency': evalCase.minUrgency?.id,
      'expected_urgency': evalCase.expectedUrgency?.id,
      'status': result?.status.id ?? 'error',
      'urgency': result?.urgency?.id,
      'escalated': result?.escalatedBySafetyRules,
      'predictions': [
        for (final p in predictions)
          {
            'name': p.name,
            'medical_term': p.medicalTerm,
            'icd10': p.icd10,
            'likelihood': p.likelihood.id,
            'serious': p.serious,
          },
      ],
      'top1': s.top1,
      'top3': s.top3,
      'weighted_top3': s.weightedTop3,
      'serious_named': s.seriousNamed,
      'under_triaged': s.underTriaged,
      'error': error,
      'cost_usd': costUsd,
      'latency_ms': latency.inMilliseconds,
    };
  }
}

/// Per-case scores. Accuracy is only defined for completed checks.
class CaseScore {
  CaseScore({
    this.top1,
    this.top3,
    this.weightedTop3,
    this.seriousNamed,
    this.underTriaged,
    this.overTriaged,
  });

  /// The top prediction matches the primary reference label.
  final bool? top1;

  /// Any of the top 3 predictions matches any reference label.
  final bool? top3;

  /// Total weight of reference labels matched in the top 3.
  final double? weightedTop3;

  /// For serious cases: a serious reference condition is in the list.
  final bool? seriousNamed;

  /// Advice is less urgent than the case requires. Retakes and declines
  /// count against this: the person didn't get the advice they needed.
  final bool? underTriaged;

  final bool? overTriaged;

  static CaseScore of(CaseOutcome o, LabelMatcher matcher) {
    final c = o.evalCase;
    final required = Urgency.maxOf(c.minUrgency, c.expectedUrgency);
    final urgency = o.result?.urgency;
    final under = required == null || o.result == null
        ? null
        : urgency == null || required.isMoreUrgentThan(urgency);
    final over = c.expectedUrgency == null || urgency == null
        ? null
        : urgency.isMoreUrgentThan(c.expectedUrgency!);

    if (!o.completed || c.labels.isEmpty) {
      return CaseScore(underTriaged: under, overTriaged: over);
    }
    final preds = o.predictions;
    final top = preds.take(3).toList();
    bool hit(Possibility p, EvalLabel l) => matcher.matches(p, l.name);

    return CaseScore(
      top1: preds.isNotEmpty && hit(preds.first, c.primaryLabel!),
      top3: c.labels.any((l) => top.any((p) => hit(p, l))),
      weightedTop3: c.labels
          .where((l) => top.any((p) => hit(p, l)))
          .fold<double>(0, (sum, l) => sum + l.weight),
      seriousNamed: c.serious
          ? preds.any((p) => c.labels.any((l) => l.weight >= 0.3 && hit(p, l)))
          : null,
      underTriaged: under,
      overTriaged: over,
    );
  }
}

class _Rate {
  int hits = 0;
  int total = 0;

  void add(bool? value) {
    if (value == null) return;
    total++;
    if (value) hits++;
  }

  double? get rate => total == 0 ? null : hits / total;

  Map<String, Object?> toJson() => {'rate': rate, 'n': total};

  String describe() => total == 0
      ? 'n/a'
      : '${(100 * hits / total).toStringAsFixed(1)}% ($hits/$total)';
}

/// Aggregate metrics for a run, plus a Markdown report.
class EvalSummary {
  EvalSummary(
    List<CaseOutcome> outcomes,
    this.matcher, {
    this.config = const {},
  }) : outcomes = List.unmodifiable(outcomes) {
    for (final o in outcomes) {
      final s = CaseScore.of(o, matcher);
      switch (o.result?.status) {
        case CheckStatus.complete:
          completed++;
        case CheckStatus.retake:
          retakes++;
        case CheckStatus.declined:
          declined++;
        case null:
          errors++;
      }
      top1.add(s.top1);
      top3.add(s.top3);
      if (s.weightedTop3 != null) {
        weightedSum += s.weightedTop3!;
        weightedN++;
      }
      seriousNamed.add(s.seriousNamed);
      if (o.evalCase.serious) seriousUnderTriaged.add(s.underTriaged);
      underTriaged.add(s.underTriaged);
      overTriaged.add(s.overTriaged);
      (byTone[_toneGroup(o.evalCase.fitzpatrick)] ??= _Rate()).add(s.top3);
      if (o.costUsd != null) cost += o.costUsd!;
      if (o.result != null) latencies.add(o.latency.inMilliseconds);

      if (o.completed && s.top1 == false && o.predictions.isNotEmpty) {
        final key =
            '${o.evalCase.primaryLabel!.name} → ${o.predictions.first.name}';
        confusions[key] = (confusions[key] ?? 0) + 1;
      }
      for (final l in o.evalCase.labels) {
        if (!matcher.knows(l.name)) {
          unknownLabels[l.name] = (unknownLabels[l.name] ?? 0) + 1;
        }
      }
    }
    latencies.sort();
  }

  final List<CaseOutcome> outcomes;
  final LabelMatcher matcher;
  final Map<String, Object?> config;

  int completed = 0;
  int retakes = 0;
  int declined = 0;
  int errors = 0;
  final top1 = _Rate();
  final top3 = _Rate();
  double weightedSum = 0;
  int weightedN = 0;
  final seriousNamed = _Rate();
  final seriousUnderTriaged = _Rate();
  final underTriaged = _Rate();
  final overTriaged = _Rate();
  final byTone = <String, _Rate>{};
  double cost = 0;
  final latencies = <int>[];
  final confusions = <String, int>{};
  final unknownLabels = <String, int>{};

  int get total => outcomes.length;

  static String _toneGroup(String? fst) => switch (fst) {
    'fst1' || 'fst2' => 'I-II',
    'fst3' || 'fst4' => 'III-IV',
    'fst5' || 'fst6' => 'V-VI',
    _ => 'unknown',
  };

  int? _percentile(double p) {
    if (latencies.isEmpty) return null;
    final i = math.min(
      latencies.length - 1,
      (p * (latencies.length - 1)).round(),
    );
    return latencies[i];
  }

  Map<String, Object?> toJson() => {
    'config': config,
    'cases': total,
    'completed': completed,
    'retakes': retakes,
    'declined': declined,
    'errors': errors,
    'top1': top1.toJson(),
    'top3': top3.toJson(),
    'weighted_top3': weightedN == 0 ? null : weightedSum / weightedN,
    'serious_named': seriousNamed.toJson(),
    'serious_under_triaged': seriousUnderTriaged.toJson(),
    'under_triaged': underTriaged.toJson(),
    'over_triaged': overTriaged.toJson(),
    'top3_by_skin_tone': {
      for (final e in byTone.entries) e.key: e.value.toJson(),
    },
    'estimated_cost_usd': cost,
    'latency_ms': {'p50': _percentile(0.5), 'p95': _percentile(0.95)},
  };

  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('# SpotCheck evaluation')
      ..writeln();
    if (config.isNotEmpty) {
      b.writeln(
        config.entries.map((e) => '`${e.key}`: ${e.value}').join(' · '),
      );
      b.writeln();
    }
    String pct(int n) =>
        total == 0 ? '0' : '${(100 * n / total).toStringAsFixed(1)}%';
    b
      ..writeln('| Metric | Value |')
      ..writeln('|---|---|')
      ..writeln('| Cases | $total |')
      ..writeln('| Completed | $completed (${pct(completed)}) |')
      ..writeln('| Retake requested | $retakes (${pct(retakes)}) |')
      ..writeln('| Declined | $declined (${pct(declined)}) |')
      ..writeln('| Errors | $errors (${pct(errors)}) |')
      ..writeln('| Top-1 accuracy | ${top1.describe()} |')
      ..writeln('| Top-3 accuracy | ${top3.describe()} |')
      ..writeln(
        '| Weighted top-3 | '
        '${weightedN == 0 ? 'n/a' : (weightedSum / weightedN).toStringAsFixed(3)} |',
      )
      ..writeln('| Serious condition named | ${seriousNamed.describe()} |')
      ..writeln(
        '| **Serious cases under-triaged** | '
        '**${seriousUnderTriaged.describe()}** |',
      )
      ..writeln(
        '| Under-triaged (all with a target) | ${underTriaged.describe()} |',
      )
      ..writeln('| Over-triaged (vs expected) | ${overTriaged.describe()} |')
      ..writeln('| Estimated cost | \$${cost.toStringAsFixed(2)} |')
      ..writeln(
        '| Latency p50 / p95 | '
        '${_fmtMs(_percentile(0.5))} / ${_fmtMs(_percentile(0.95))} |',
      )
      ..writeln()
      ..writeln('## Top-3 accuracy by skin tone (Fitzpatrick)')
      ..writeln()
      ..writeln('| Group | Top-3 |')
      ..writeln('|---|---|');
    for (final group in ['I-II', 'III-IV', 'V-VI', 'unknown']) {
      final r = byTone[group];
      if (r != null) b.writeln('| $group | ${r.describe()} |');
    }
    if (confusions.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Most common top-1 misses (reference → predicted)')
        ..writeln();
      for (final e in _top(confusions, 15)) {
        b.writeln('- ${e.key} ×${e.value}');
      }
    }
    if (unknownLabels.isNotEmpty) {
      b
        ..writeln()
        ..writeln(
          '## Reference labels without a synonym entry '
          '(matched by exact phrase only)',
        )
        ..writeln();
      for (final e in _top(unknownLabels, 15)) {
        b.writeln('- ${e.key} ×${e.value}');
      }
    }
    return b.toString();
  }

  static List<MapEntry<String, int>> _top(Map<String, int> m, int n) =>
      (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .take(n)
          .toList();

  static String _fmtMs(int? ms) =>
      ms == null ? 'n/a' : '${(ms / 1000).toStringAsFixed(1)}s';
}
