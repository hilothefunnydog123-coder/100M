import 'package:spotcheck_core/spotcheck_core.dart';
import 'package:test/test.dart';

/// Builds answers, failing loudly on any id that isn't in the catalog so a
/// typo in a test can't silently pass.
IntakeAnswers answers(Map<String, List<String>> raw) {
  for (final e in raw.entries) {
    final q = IntakeCatalog.byId(e.key);
    expect(q, isNotNull, reason: 'Unknown question ${e.key}');
    for (final o in e.value) {
      expect(q!.option(o), isNotNull, reason: 'Unknown option ${e.key}.$o');
    }
  }
  return IntakeAnswers({for (final e in raw.entries) e.key: e.value.toSet()});
}

ModelAssessment assessment({
  Urgency urgency = Urgency.selfCare,
  CareSetting careSetting = CareSetting.selfCare,
  bool usable = true,
  String retakeAdvice = '',
}) => ModelAssessment(
  imageQuality: ImageQuality(
    usable: usable,
    issues: usable ? const [] : const [PhotoIssue.blurry],
    retakeAdvice: retakeAdvice,
  ),
  urgency: urgency,
  careSetting: careSetting,
  headline: 'Looks like mild eczema',
  possibilities: const [
    Possibility(name: 'Eczema', likelihood: Likelihood.high, icd10: 'L20.9'),
  ],
);
