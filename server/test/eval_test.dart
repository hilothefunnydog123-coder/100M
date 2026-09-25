import 'package:spotcheck_core/spotcheck_core.dart';
import 'package:spotcheck_server/eval.dart';
import 'package:test/test.dart';

Possibility p(String name, {String term = ''}) =>
    Possibility(name: name, medicalTerm: term, likelihood: Likelihood.high);

CheckResult complete(
  List<Possibility> predictions, {
  Urgency urgency = Urgency.selfCare,
}) => CheckResult(
  id: 'x',
  status: CheckStatus.complete,
  createdAt: DateTime.utc(2026),
  urgency: urgency,
  assessment: ModelAssessment(
    imageQuality: const ImageQuality(usable: true),
    urgency: urgency,
    careSetting: CareSetting.defaultFor(urgency),
    possibilities: predictions,
  ),
);

EvalCase evalCase(
  List<(String, double)> labels, {
  bool serious = false,
  Urgency? minUrgency,
  String? fitzpatrick,
}) => EvalCase(
  id: 'c',
  site: BodySite.arm,
  answers: IntakeAnswers.empty,
  images: const [],
  labels: [for (final (n, w) in labels) EvalLabel(n, w)],
  serious: serious,
  minUrgency: minUrgency,
  fitzpatrick: fitzpatrick,
);

void main() {
  final matcher = LabelMatcher();

  group('LabelMatcher', () {
    test('matches synonyms across naming styles', () {
      expect(matcher.matches(p('Eczema'), 'Acute dermatitis, NOS'), isTrue);
      expect(
        matcher.matches(p('Eczema', term: 'Atopic dermatitis'), 'Eczema'),
        isTrue,
      );
      expect(
        matcher.matches(p('Contact dermatitis'), 'CD - Contact dermatitis'),
        isTrue,
      );
      expect(matcher.matches(p('Hives'), 'Urticaria'), isTrue);
      expect(matcher.matches(p('Shingles'), 'Herpes Zoster'), isTrue);
      expect(matcher.matches(p('Bruise'), 'O/E - ecchymoses present'), isTrue);
      expect(
        matcher.matches(p('Squamous cell carcinoma'), 'SCC/SCCIS'),
        isTrue,
      );
      expect(matcher.matches(p('Ringworm'), 'Tinea'), isTrue);
    });

    test('the longest alias wins', () {
      expect(matcher.conceptsOf('Tinea versicolor'), {'tinea_versicolor'});
      expect(matcher.matches(p('Tinea corporis'), 'Tinea Versicolor'), isFalse);
      expect(matcher.conceptsOf('Papular urticaria'), {'insect_bite'});
      expect(matcher.matches(p('Hives'), 'Papular urticaria'), isFalse);
    });

    test('does not match different conditions', () {
      expect(matcher.matches(p('Eczema'), 'Psoriasis'), isFalse);
      expect(
        matcher.matches(p('Skin cancer'), 'Basal Cell Carcinoma'),
        isFalse,
      );
      expect(
        matcher.matches(p('Seborrheic keratosis'), 'Actinic Keratosis'),
        isFalse,
      );
    });

    test('falls back to phrase matching for unknown labels', () {
      expect(matcher.knows('Inflicted skin lesions'), isFalse);
      expect(
        matcher.matches(p('Inflicted skin lesions'), 'Inflicted skin lesions'),
        isTrue,
      );
      expect(matcher.matches(p('Eczema'), 'Inflicted skin lesions'), isFalse);
    });
  });

  group('scoring', () {
    test('top-1, top-3, and weighted top-3', () {
      final o = CaseOutcome(
        evalCase: evalCase([('Eczema', 0.6), ('Psoriasis', 0.4)]),
        result: complete([
          p('Contact dermatitis'),
          p('Psoriasis'),
          p('Eczema'),
        ]),
      );
      final s = CaseScore.of(o, matcher);
      expect(s.top1, isFalse);
      expect(s.top3, isTrue);
      expect(s.weightedTop3, closeTo(1.0, 1e-9));
    });

    test('serious cases: named and under-triage', () {
      final missed = CaseOutcome(
        evalCase: evalCase(
          [('Melanoma', 0.7)],
          serious: true,
          minUrgency: Urgency.routine,
        ),
        result: complete([p('Common mole')]),
      );
      final caught = CaseOutcome(
        evalCase: evalCase(
          [('Melanoma', 0.7)],
          serious: true,
          minUrgency: Urgency.routine,
        ),
        result: complete([
          p('Atypical mole'),
          p('Melanoma'),
        ], urgency: Urgency.routine),
      );
      expect(CaseScore.of(missed, matcher).seriousNamed, isFalse);
      expect(CaseScore.of(missed, matcher).underTriaged, isTrue);
      expect(CaseScore.of(caught, matcher).seriousNamed, isTrue);
      expect(CaseScore.of(caught, matcher).underTriaged, isFalse);
    });

    test('a retake without urgency counts as under-triage', () {
      final o = CaseOutcome(
        evalCase: evalCase(
          [('Cellulitis', 1)],
          serious: true,
          minUrgency: Urgency.soon,
        ),
        result: CheckResult(
          id: 'x',
          status: CheckStatus.retake,
          createdAt: DateTime.utc(2026),
        ),
      );
      final s = CaseScore.of(o, matcher);
      expect(s.underTriaged, isTrue);
      expect(s.top3, isNull, reason: 'accuracy only counts completed checks');
    });

    test('summary aggregates and renders a report', () {
      final summary = EvalSummary([
        CaseOutcome(
          evalCase: evalCase([('Eczema', 1)], fitzpatrick: 'fst5'),
          result: complete([p('Eczema')]),
          costUsd: 0.10,
          latency: const Duration(seconds: 20),
        ),
        CaseOutcome(
          evalCase: evalCase([('Psoriasis', 1)], fitzpatrick: 'fst2'),
          result: complete([p('Eczema')]),
          costUsd: 0.12,
          latency: const Duration(seconds: 30),
        ),
        CaseOutcome(evalCase: evalCase([('Acne', 1)]), error: 'boom'),
      ], matcher);
      expect(summary.total, 3);
      expect(summary.completed, 2);
      expect(summary.errors, 1);
      expect(summary.top1.rate, 0.5);
      expect(summary.cost, closeTo(0.22, 1e-9));
      final json = summary.toJson();
      expect(
        (json['top3_by_skin_tone'] as Map).keys,
        containsAll(['V-VI', 'I-II']),
      );
      final md = summary.toMarkdown();
      expect(md, contains('Top-1 accuracy | 50.0% (1/2)'));
      expect(md, contains('Psoriasis → Eczema ×1'));
    });
  });
}
