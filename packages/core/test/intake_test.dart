import 'package:spotcheck_core/spotcheck_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('IntakeCatalog', () {
    test('question ids are unique', () {
      final ids = IntakeCatalog.all.map((q) => q.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('option ids are unique within each question', () {
      for (final q in IntakeCatalog.all) {
        final ids = q.options.map((o) => o.id).toList();
        expect(ids.toSet().length, ids.length, reason: q.id);
        expect(q.options, isNotEmpty, reason: q.id);
      }
    });

    test('showIf conditions reference real, earlier questions and options', () {
      final seen = <String>{};
      for (final q in IntakeCatalog.all) {
        final cond = q.showIf;
        if (cond != null) {
          expect(seen, contains(cond.questionId), reason: q.id);
          final parent = IntakeCatalog.byId(cond.questionId)!;
          for (final o in cond.anyOf) {
            expect(parent.option(o), isNotNull, reason: '${q.id} -> $o');
          }
        }
        seen.add(q.id);
      }
    });

    test('single-choice questions have no exclusive options', () {
      for (final q in IntakeCatalog.all.where(
        (q) => q.kind == QuestionKind.single,
      )) {
        expect(q.options.where((o) => o.exclusive), isEmpty, reason: q.id);
      }
    });

    test('every domain asks about age, duration, and general symptoms', () {
      for (final d in Domain.values) {
        final ids = IntakeCatalog.visibleQuestions(
          d,
          IntakeAnswers.empty,
        ).map((q) => q.id);
        expect(
          ids,
          containsAll([Q.ageBand, Q.duration, Q.generalSymptoms]),
          reason: d.id,
        );
      }
    });

    test('follow-up questions appear only when relevant', () {
      final base = IntakeCatalog.visibleQuestions(
        Domain.skin,
        IntakeAnswers.empty,
      ).map((q) => q.id);
      expect(base, isNot(contains(Q.moleFeatures)));

      final mole = IntakeCatalog.visibleQuestions(
        Domain.skin,
        answers({
          Q.skinKind: ['mole'],
        }),
      ).map((q) => q.id);
      expect(mole, contains(Q.moleFeatures));
      expect(mole, isNot(contains(Q.glassTest)));

      final rash = IntakeCatalog.visibleQuestions(
        Domain.skin,
        answers({
          Q.skinKind: ['rash'],
        }),
      ).map((q) => q.id);
      expect(rash, containsAll([Q.glassTest, Q.exposures]));
    });

    test('eye checks do not ask skin questions', () {
      final ids = IntakeCatalog.visibleQuestions(
        Domain.eye,
        IntakeAnswers.empty,
      ).map((q) => q.id);
      expect(ids, contains(Q.eyeSymptoms));
      expect(ids, isNot(contains(Q.skinKind)));
      expect(ids, isNot(contains(Q.localSymptoms)));
    });

    test('describe renders question and chosen labels', () {
      final lines = IntakeCatalog.describe(
        Domain.skin,
        answers({
          Q.skinKind: ['rash'],
          Q.localSymptoms: ['itchy', 'burning'],
        }),
      );
      expect(lines, contains('What best describes it? A rash or red patch'));
      expect(lines, contains('Does it… Itch; Burn or sting'));
    });
  });

  group('IntakeAnswers', () {
    final symptoms = IntakeCatalog.byId(Q.localSymptoms)!;
    final kind = IntakeCatalog.byId(Q.skinKind)!;

    test('toggle adds and removes multi-choice options', () {
      var a = IntakeAnswers.empty.toggle(symptoms, 'itchy');
      a = a.toggle(symptoms, 'painful');
      expect(a[Q.localSymptoms], {'itchy', 'painful'});
      a = a.toggle(symptoms, 'itchy');
      expect(a[Q.localSymptoms], {'painful'});
    });

    test('exclusive option clears others and vice versa', () {
      var a = IntakeAnswers.empty
          .toggle(symptoms, 'itchy')
          .toggle(symptoms, 'painful');
      a = a.toggle(symptoms, 'none');
      expect(a[Q.localSymptoms], {'none'});
      a = a.toggle(symptoms, 'warm');
      expect(a[Q.localSymptoms], {'warm'});
    });

    test('single choice replaces the previous answer', () {
      final a = IntakeAnswers.empty.toggle(kind, 'mole').toggle(kind, 'rash');
      expect(a.single(Q.skinKind), 'rash');
    });

    test('unknown options are ignored by toggle', () {
      final a = IntakeAnswers.empty.toggle(kind, 'not_a_thing');
      expect(a.isAnswered(Q.skinKind), isFalse);
    });

    test('removing the last option clears the question', () {
      final a = IntakeAnswers.empty
          .toggle(symptoms, 'itchy')
          .toggle(symptoms, 'itchy');
      expect(a.isAnswered(Q.localSymptoms), isFalse);
    });

    test('fromJson drops unknown questions and options', () {
      final a = IntakeAnswers.fromJson({
        'skin_kind': ['rash'],
        'local_symptoms': ['itchy', 'made_up'],
        'unknown_question': ['x'],
        'duration': 'not a list',
      });
      expect(a.toJson(), {
        'skin_kind': ['rash'],
        'local_symptoms': ['itchy'],
      });
    });

    test('fromJson enforces single choice and exclusivity', () {
      final a = IntakeAnswers.fromJson({
        'skin_kind': ['rash', 'mole'],
        'local_symptoms': ['itchy', 'none'],
      });
      expect(a[Q.skinKind], hasLength(1));
      expect(a[Q.localSymptoms], {'none'});
    });

    test('fromJson tolerates garbage', () {
      expect(IntakeAnswers.fromJson(null), IntakeAnswers.empty);
      expect(IntakeAnswers.fromJson('nope'), IntakeAnswers.empty);
      expect(IntakeAnswers.fromJson([1, 2]), IntakeAnswers.empty);
    });

    test('prunedFor removes answers to hidden questions', () {
      final a = answers({
        Q.skinKind: ['rash'],
        Q.moleFeatures: ['asymmetric'],
        Q.eyeSymptoms: ['red'],
        Q.duration: ['1_6d'],
      });
      final pruned = a.prunedFor(Domain.skin);
      expect(pruned.isAnswered(Q.moleFeatures), isFalse);
      expect(pruned.isAnswered(Q.eyeSymptoms), isFalse);
      expect(pruned.isAnswered(Q.duration), isTrue);
      expect(pruned.isAnswered(Q.skinKind), isTrue);
    });

    test('equality ignores ordering', () {
      final a = answers({
        Q.localSymptoms: ['itchy', 'warm'],
      });
      final b = answers({
        Q.localSymptoms: ['warm', 'itchy'],
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('JSON round trip', () {
      final a = answers({
        Q.skinKind: ['mole'],
        Q.moleFeatures: ['asymmetric', 'evolving'],
      });
      expect(IntakeAnswers.fromJson(a.toJson()), a);
    });
  });
}
