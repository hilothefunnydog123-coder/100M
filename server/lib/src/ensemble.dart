import 'package:spotcheck_core/spotcheck_core.dart';

/// Combines several independent assessments of the same check.
///
/// Sampling the model more than once and merging is a simple way to reduce
/// variance: urgency takes the most cautious run, serious possibilities
/// raised by any run are kept, and disagreement on the leading possibility
/// lowers the reported confidence.
abstract final class Ensemble {
  static ModelAssessment combine(List<ModelAssessment> runs) {
    if (runs.isEmpty) throw ArgumentError('No assessments to combine.');
    if (runs.length == 1) return runs.single;

    final usable = runs.where((r) => r.imageQuality.usable).toList();
    // Most runs must find the photos usable; otherwise ask for a retake.
    if (usable.length * 2 < runs.length) {
      final unusable = runs.firstWhere((r) => !r.imageQuality.usable);
      return ModelAssessment(
        imageQuality: unusable.imageQuality,
        urgency: _maxUrgency(runs),
        careSetting: unusable.careSetting,
        headline: unusable.headline,
        confidence: Confidence.low,
        confidenceNote: unusable.confidenceNote,
      );
    }

    final urgency = _maxUrgency(usable);
    // Text comes from a run that reached the final urgency, so the
    // explanation matches the advice.
    final primary = usable.firstWhere((r) => r.urgency == urgency);

    return ModelAssessment(
      imageQuality: primary.imageQuality,
      headline: primary.headline,
      observationSummary: primary.observationSummary,
      observedFeatures: primary.observedFeatures,
      possibilities: _mergePossibilities(usable, primary),
      urgency: urgency,
      urgencyReason: primary.urgencyReason,
      careSetting: primary.careSetting,
      redFlags: _union([for (final r in usable) ...r.redFlags]),
      watchFor: primary.watchFor,
      selfCare: primary.selfCare,
      doctorQuestions: primary.doctorQuestions,
      confidence: _confidence(usable),
      confidenceNote: primary.confidenceNote,
    );
  }

  /// A stable key for matching the same condition across runs: the ICD-10
  /// category when present (e.g. "L20"), otherwise the normalized name.
  static String conditionKey(Possibility p) {
    final code = RegExp(
      r'^[A-Z][0-9]{2}',
    ).firstMatch(p.icd10.trim().toUpperCase());
    if (code != null) return code.group(0)!;
    return p.name
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  static Urgency _maxUrgency(List<ModelAssessment> runs) =>
      runs.map((r) => r.urgency).reduce((a, b) => Urgency.maxOf(a, b)!);

  static int _weight(Likelihood l) => switch (l) {
    Likelihood.high => 3,
    Likelihood.moderate => 2,
    Likelihood.low => 1,
  };

  static List<Possibility> _mergePossibilities(
    List<ModelAssessment> runs,
    ModelAssessment primary,
  ) {
    final score = <String, int>{};
    final serious = <String, bool>{};
    final representative = <String, Possibility>{};
    for (final p in primary.possibilities) {
      representative[conditionKey(p)] = p;
    }
    for (final run in runs) {
      for (final p in run.possibilities) {
        final key = conditionKey(p);
        score[key] = (score[key] ?? 0) + _weight(p.likelihood);
        serious[key] = (serious[key] ?? false) || p.serious;
        representative.putIfAbsent(key, () => p);
      }
    }

    Likelihood likelihoodFor(String key) {
      final average = score[key]! / runs.length;
      if (average >= 2.5) return Likelihood.high;
      if (average >= 1.5) return Likelihood.moderate;
      return Likelihood.low;
    }

    final ranked = score.keys.toList()
      ..sort((a, b) => score[b]!.compareTo(score[a]!));
    var kept = ranked.take(ModelAssessment.maxPossibilities).toList();
    // Never drop a serious possibility that any run raised.
    for (final key in ranked.skip(ModelAssessment.maxPossibilities)) {
      if (serious[key]! && kept.any((k) => !serious[k]!)) {
        final lastBenign = kept.lastIndexWhere((k) => !serious[k]!);
        kept = [...kept]..[lastBenign] = key;
      }
    }

    return [
      for (final key in kept)
        Possibility(
          name: representative[key]!.name,
          medicalTerm: representative[key]!.medicalTerm,
          icd10: representative[key]!.icd10,
          likelihood: likelihoodFor(key),
          description: representative[key]!.description,
          supportingFeatures: representative[key]!.supportingFeatures,
          serious: serious[key]!,
        ),
    ];
  }

  static Confidence _confidence(List<ModelAssessment> runs) {
    final leaders = {
      for (final r in runs)
        if (r.possibilities.isNotEmpty) conditionKey(r.possibilities.first),
    };
    if (leaders.length > 1) return Confidence.low;
    return runs
        .map((r) => r.confidence)
        .reduce((a, b) => a.index >= b.index ? a : b);
  }

  static List<String> _union(List<String> items) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (seen.add(item.toLowerCase())) item,
    ].take(ModelAssessment.maxListItems).toList();
  }
}
