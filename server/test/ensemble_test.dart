import 'package:spotcheck_core/spotcheck_core.dart';
import 'package:spotcheck_server/spotcheck_server.dart';
import 'package:test/test.dart';

import 'fakes.dart';

ModelAssessment run({
  String urgency = 'self_care',
  bool usable = true,
  List<Map<String, Object?>>? possibilities,
  String confidence = 'high',
  List<String> redFlags = const [],
}) => ModelAssessment.fromJson(
  assessmentJson(
    urgency: urgency,
    usable: usable,
    possibilities: possibilities,
    confidence: confidence,
    redFlags: redFlags,
  ),
);

void main() {
  test('a single run passes through unchanged', () {
    final a = run();
    expect(Ensemble.combine([a]), same(a));
  });

  test('urgency is the most cautious run', () {
    final c = Ensemble.combine([
      run(),
      run(urgency: 'routine'),
      run(urgency: 'soon'),
    ]);
    expect(c.urgency, Urgency.soon);
  });

  test('possibilities are ranked by agreement and likelihood', () {
    final c = Ensemble.combine([
      run(
        possibilities: [
          possibility('Eczema', 'L20.9', 'high'),
          possibility('Psoriasis', 'L40.0', 'low'),
        ],
      ),
      run(
        possibilities: [
          possibility('Atopic eczema', 'L20.8', 'high'),
          possibility('Tinea', 'B35.4', 'moderate'),
        ],
      ),
    ]);
    // L20.9 and L20.8 share the L20 category, so they merge.
    expect(c.possibilities.first.name, 'Eczema');
    expect(c.possibilities.first.likelihood, Likelihood.high);
    expect(c.possibilities.map((p) => p.name), contains('Tinea'));
    final tinea = c.possibilities.firstWhere((p) => p.name == 'Tinea');
    expect(tinea.likelihood, Likelihood.low);
  });

  test('a serious possibility raised by one run is never dropped', () {
    List<Map<String, Object?>> benign(String prefix) => [
      for (var i = 0; i < 5; i++)
        possibility('$prefix $i', 'L${50 + i}', 'high'),
    ];
    final c = Ensemble.combine([
      run(possibilities: benign('Benign')),
      run(
        possibilities: [
          ...benign('Benign').take(4),
          possibility('Melanoma', 'C43.9', 'low', serious: true),
        ],
      ),
    ]);
    expect(c.possibilities, hasLength(ModelAssessment.maxPossibilities));
    final melanoma = c.possibilities.where((p) => p.name == 'Melanoma');
    expect(melanoma, hasLength(1));
    expect(melanoma.single.serious, isTrue);
  });

  test('disagreement on the leading possibility lowers confidence', () {
    final c = Ensemble.combine([
      run(possibilities: [possibility('Eczema', 'L20.9', 'high')]),
      run(possibilities: [possibility('Psoriasis', 'L40.0', 'high')]),
    ]);
    expect(c.confidence, Confidence.low);
  });

  test('agreement keeps the lowest stated confidence', () {
    final c = Ensemble.combine([
      run(confidence: 'high'),
      run(confidence: 'moderate'),
    ]);
    expect(c.confidence, Confidence.moderate);
  });

  test('red flags are unioned without duplicates', () {
    final c = Ensemble.combine([
      run(redFlags: ['Uneven color']),
      run(redFlags: ['uneven color', 'Bleeding']),
    ]);
    expect(c.redFlags, ['Uneven color', 'Bleeding']);
  });

  test('a majority of unusable photos means retake', () {
    final c = Ensemble.combine([
      run(usable: false),
      run(usable: false, urgency: 'soon'),
      run(),
    ]);
    expect(c.imageQuality.usable, isFalse);
    expect(c.urgency, Urgency.soon);
  });

  test('conditionKey uses the ICD-10 category, then the name', () {
    Possibility p(String name, String code) =>
        Possibility(name: name, icd10: code, likelihood: Likelihood.low);
    expect(Ensemble.conditionKey(p('Eczema', 'l20.9')), 'L20');
    expect(
      Ensemble.conditionKey(p('Contact Dermatitis (allergic)', '')),
      'contact dermatitis',
    );
  });
}
