import 'dart:convert';
import 'dart:typed_data';

import 'package:spotcheck_core/spotcheck_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]);
final png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
]);
final webp = Uint8List.fromList(utf8.encode('RIFF\x00\x00\x00\x00WEBPVP8 '));

Map<String, Object?> modelOutput({String urgency = 'routine'}) => {
  'image_quality': {'usable': true, 'issues': <String>[], 'retake_advice': ''},
  'observations': {
    'summary': 'A 5 mm brown spot with uneven color.',
    'features': ['Two shades of brown', 'Slightly irregular edge'],
  },
  'possibilities': [
    {
      'name': 'Atypical mole',
      'medical_term': 'Dysplastic nevus',
      'icd10': 'D22.5',
      'likelihood': 'high',
      'description': 'A mole that looks unusual.',
      'supporting_features': 'Uneven color.',
      'serious': false,
    },
    {
      'name': 'Melanoma',
      'medical_term': 'Melanoma',
      'icd10': 'C43.5',
      'likelihood': 'low',
      'description': 'A skin cancer.',
      'supporting_features': 'Irregular edge.',
      'serious': true,
    },
  ],
  'urgency': urgency,
  'urgency_reason': 'Uneven color is worth a dermatologist look.',
  'care_setting': 'dermatologist',
  'red_flags': ['Two colors'],
  'watch_for': ['Bleeding', 'Growth'],
  'self_care': ['Protect it from the sun'],
  'doctor_questions': ['Should this be removed?'],
  'confidence': 'moderate',
  'confidence_note': 'Photos cannot show fine detail.',
  'headline': 'An unusual-looking mole worth checking',
};

void main() {
  group('ModelAssessment', () {
    test('parses model output', () {
      final a = ModelAssessment.fromJson(modelOutput());
      expect(a.urgency, Urgency.routine);
      expect(a.careSetting, CareSetting.dermatologist);
      expect(a.possibilities, hasLength(2));
      expect(a.possibilities.last.serious, isTrue);
      expect(a.possibilities.first.likelihood, Likelihood.high);
      expect(a.observedFeatures, hasLength(2));
      expect(a.confidence, Confidence.moderate);
    });

    test('round-trips through JSON', () {
      final a = ModelAssessment.fromJson(modelOutput());
      final b = ModelAssessment.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Map<String, Object?>,
      );
      expect(b.toJson(), a.toJson());
    });

    test('rejects a missing or invalid urgency', () {
      expect(
        () => ModelAssessment.fromJson(modelOutput(urgency: 'whenever')),
        throwsFormatException,
      );
      expect(
        () => ModelAssessment.fromJson({...modelOutput()}..remove('urgency')),
        throwsFormatException,
      );
    });

    test('rejects missing image quality', () {
      expect(
        () => ModelAssessment.fromJson(
          {...modelOutput()}..remove('image_quality'),
        ),
        throwsFormatException,
      );
    });

    test('bounds lists and strings', () {
      final json = modelOutput()
        ..['possibilities'] = List.generate(
          9,
          (i) => {'name': 'Condition $i', 'likelihood': 'weird'},
        )
        ..['watch_for'] = List.generate(20, (i) => 'Sign $i')
        ..['headline'] = 'x' * 5000;
      final a = ModelAssessment.fromJson(json);
      expect(a.possibilities, hasLength(ModelAssessment.maxPossibilities));
      expect(a.possibilities.first.likelihood, Likelihood.low);
      expect(a.watchFor, hasLength(ModelAssessment.maxListItems));
      expect(a.headline.length, lessThanOrEqualTo(800));
    });

    test('falls back to a care setting that matches the urgency', () {
      final a = ModelAssessment.fromJson(
        modelOutput(urgency: 'urgent')..remove('care_setting'),
      );
      expect(a.careSetting, CareSetting.urgentCare);
    });
  });

  group('CheckResult', () {
    test('round-trips through JSON', () {
      final result = Triage.merge(
        id: newId('chk'),
        assessment: ModelAssessment.fromJson(modelOutput()),
        safety: SafetyRules.evaluate(
          BodySite.back,
          answers({
            Q.skinKind: ['mole'],
            Q.moleFeatures: ['multi_color'],
          }),
        ),
        createdAt: DateTime.utc(2026, 9, 25),
        model: 'claude-opus-5-5',
      );
      final decoded = CheckResult.fromJson(
        jsonDecode(jsonEncode(result.toJson())) as Map<String, Object?>,
      );
      expect(decoded.toJson(), result.toJson());
      expect(decoded.urgency, Urgency.routine);
      expect(decoded.safetyNotes.single.ruleId, 'mole_warning_signs');
    });
  });

  group('CheckRequest.fromJson', () {
    Map<String, Object?> body({
      Object? site = 'arm',
      Object? photos,
      Object? note = '',
      Object? answers,
    }) => {
      'site': site,
      'answers':
          answers ??
          {
            'skin_kind': ['rash'],
            'eye_symptoms': ['red'],
          },
      'note': note,
      'photos':
          photos ??
          [
            {
              'media_type': 'image/png',
              'kind': 'close_up',
              'data': base64Encode(jpeg),
            },
          ],
    };

    test('accepts a valid request and sniffs the real media type', () {
      final r = CheckRequest.fromJson(body());
      expect(r.site, BodySite.arm);
      expect(r.photos.single.mediaType, 'image/jpeg');
      // Eye answers don't apply to an arm and are pruned.
      expect(r.answers.isAnswered(Q.eyeSymptoms), isFalse);
      expect(r.answers.single(Q.skinKind), 'rash');
    });

    test('recognises PNG and WebP', () {
      final r = CheckRequest.fromJson(
        body(
          photos: [
            {'data': base64Encode(png), 'kind': 'context'},
            {'data': base64Encode(webp)},
          ],
        ),
      );
      expect(r.photos.map((p) => p.mediaType), ['image/png', 'image/webp']);
      expect(r.photos.first.kind, PhotoKind.context);
    });

    test('truncates long notes', () {
      final r = CheckRequest.fromJson(body(note: 'a' * 2000));
      expect(r.note.length, CheckRequest.maxNoteLength);
    });

    for (final (name, bad) in [
      ('non-object body', ['nope']),
      ('unknown site', body(site: 'groin')),
      ('no photos', body(photos: <Object?>[])),
      (
        'too many photos',
        body(photos: List.generate(4, (_) => {'data': base64Encode(jpeg)})),
      ),
      (
        'bad base64',
        body(
          photos: [
            {'data': '!!!'},
          ],
        ),
      ),
      (
        'not an image',
        body(
          photos: [
            {'data': base64Encode(utf8.encode('<html>hi</html>'))},
          ],
        ),
      ),
      (
        'oversized photo',
        body(
          photos: [
            {'data': 'A' * (CheckRequest.maxPhotoBytes * 2)},
          ],
        ),
      ),
    ]) {
      test('rejects $name', () {
        expect(
          () => CheckRequest.fromJson(bad),
          throwsA(isA<InvalidCheckRequest>()),
        );
      });
    }

    test('toJson/fromJson round trip', () {
      final request = CheckRequest(
        site: BodySite.nail,
        answers: answers({
          Q.nailSymptoms: ['dark_streak'],
        }),
        photos: [CheckPhoto(bytes: jpeg, mediaType: 'image/jpeg')],
        note: 'Appeared last month',
      );
      final back = CheckRequest.fromJson(
        jsonDecode(jsonEncode(request.toJson())),
      );
      expect(back.site, BodySite.nail);
      expect(back.answers, request.answers);
      expect(back.note, 'Appeared last month');
      expect(back.photos.single.bytes, jpeg);
    });
  });

  group('doctor summary', () {
    test('includes history, possibilities, urgency, and disclaimer', () {
      final a = answers({
        Q.skinKind: ['mole'],
        Q.moleFeatures: ['multi_color'],
      });
      final result = Triage.merge(
        id: 'chk_x',
        assessment: ModelAssessment.fromJson(modelOutput()),
        safety: SafetyRules.evaluate(BodySite.back, a),
        createdAt: DateTime.utc(2026, 9, 25, 9, 30),
      );
      final text = formatDoctorSummary(
        site: BodySite.back,
        answers: a,
        result: result,
        note: 'Noticed it in the mirror',
      );
      expect(text, contains('Area: Back'));
      expect(text, contains('What best describes it? A mole or dark spot'));
      expect(text, contains('Note: Noticed it in the mirror'));
      expect(text, contains('Atypical mole (Dysplastic nevus) [D22.5]'));
      expect(text, contains('not a diagnosis'));
      expect(text, contains('Suggested urgency: Book a doctor visit'));
      expect(text, isNot(contains('DEMO')));
    });
  });

  test('newId is prefixed, random, and URL-safe', () {
    final ids = List.generate(200, (_) => newId('chk'));
    expect(ids.toSet(), hasLength(200));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^chk_[a-z0-9]{20}$')));
    }
  });

  test('sniffImageType rejects short and unknown input', () {
    expect(sniffImageType([]), isNull);
    expect(sniffImageType([0xFF, 0xD8]), isNull);
    expect(sniffImageType(utf8.encode('GIF89a')), isNull);
  });
}
