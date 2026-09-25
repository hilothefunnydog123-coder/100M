import 'package:spotcheck_core/spotcheck_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final now = DateTime.utc(2026, 9, 25, 12);

  SafetyEvaluation safety(BodySite site, Map<String, List<String>> raw) =>
      SafetyRules.evaluate(site, answers(raw));

  group('Triage.merge', () {
    test('keeps the model urgency when no rule applies', () {
      final r = Triage.merge(
        id: 'chk_1',
        assessment: assessment(urgency: Urgency.selfCare),
        safety: safety(BodySite.arm, {
          Q.skinKind: ['acne'],
        }),
        createdAt: now,
      );
      expect(r.status, CheckStatus.complete);
      expect(r.urgency, Urgency.selfCare);
      expect(r.escalatedBySafetyRules, isFalse);
      expect(r.safetyNotes, isEmpty);
      expect(r.careSetting, CareSetting.selfCare);
    });

    test('rules raise a lower model urgency', () {
      final r = Triage.merge(
        id: 'chk_2',
        assessment: assessment(urgency: Urgency.selfCare),
        safety: safety(BodySite.back, {
          Q.skinKind: ['mole'],
          Q.moleFeatures: ['evolving'],
        }),
        createdAt: now,
      );
      expect(r.urgency, Urgency.routine);
      expect(r.escalatedBySafetyRules, isTrue);
      expect(r.careSetting, CareSetting.dermatologist);
      expect(
        r.safetyNotes.map((n) => n.ruleId),
        contains('mole_warning_signs'),
      );
    });

    test('rules never lower a higher model urgency', () {
      final r = Triage.merge(
        id: 'chk_3',
        assessment: assessment(
          urgency: Urgency.urgent,
          careSetting: CareSetting.urgentCare,
        ),
        safety: safety(BodySite.back, {
          Q.skinKind: ['mole'],
          Q.moleFeatures: ['asymmetric'],
        }),
        createdAt: now,
      );
      expect(r.urgency, Urgency.urgent);
      expect(r.escalatedBySafetyRules, isFalse);
      expect(r.careSetting, CareSetting.urgentCare);
    });

    test('an unfit model care setting is replaced', () {
      final r = Triage.merge(
        id: 'chk_4',
        assessment: assessment(
          urgency: Urgency.selfCare,
          careSetting: CareSetting.pharmacist,
        ),
        safety: safety(BodySite.arm, {
          Q.skinKind: ['rash'],
          Q.generalSymptoms: ['trouble_breathing'],
        }),
        createdAt: now,
      );
      expect(r.urgency, Urgency.emergency);
      expect(r.careSetting, CareSetting.emergencyRoom);
    });

    test('an unusable photo becomes a retake that keeps the rule floor', () {
      final r = Triage.merge(
        id: 'chk_5',
        assessment: assessment(usable: false, retakeAdvice: 'Use daylight.'),
        safety: safety(BodySite.leg, {
          Q.skinKind: ['rash'],
          Q.generalSymptoms: ['fever'],
        }),
        createdAt: now,
      );
      expect(r.status, CheckStatus.retake);
      expect(r.urgency, Urgency.soon);
      expect(r.message, 'Use daylight.');
      expect(r.careSetting, CareSetting.primaryCare);
    });

    test('a retake without rules has no urgency and a default message', () {
      final r = Triage.merge(
        id: 'chk_6',
        assessment: assessment(usable: false),
        safety: safety(BodySite.arm, {
          Q.skinKind: ['acne'],
        }),
        createdAt: now,
      );
      expect(r.status, CheckStatus.retake);
      expect(r.urgency, isNull);
      expect(r.careSetting, isNull);
      expect(r.message, Triage.defaultRetakeMessage);
    });
  });

  test('a declined check still carries the rule floor', () {
    final r = Triage.declined(
      id: 'chk_7',
      safety: safety(BodySite.eye, {
        Q.eyeSymptoms: ['chemical'],
      }),
      createdAt: now,
    );
    expect(r.status, CheckStatus.declined);
    expect(r.urgency, Urgency.emergency);
    expect(r.assessment, isNull);
    expect(r.safetyNotes.single.action, contains('15 minutes'));
  });

  group('Urgency and CareSetting', () {
    test('ordering', () {
      expect(Urgency.emergency.isMoreUrgentThan(Urgency.urgent), isTrue);
      expect(Urgency.routine.isAtLeast(Urgency.routine), isTrue);
      expect(Urgency.maxOf(Urgency.soon, Urgency.routine), Urgency.soon);
      expect(Urgency.maxOf(null, Urgency.routine), Urgency.routine);
      expect(Urgency.maxOf(null, null), isNull);
    });

    test('default care settings fit their urgency', () {
      for (final u in Urgency.values) {
        expect(CareSetting.defaultFor(u).fits(u), isTrue, reason: u.id);
      }
    });

    test('a same-day need is not met by self care', () {
      expect(CareSetting.selfCare.fits(Urgency.urgent), isFalse);
      expect(CareSetting.dermatologist.fits(Urgency.emergency), isFalse);
      expect(CareSetting.eyeDoctor.fits(Urgency.urgent), isTrue);
    });
  });
}
