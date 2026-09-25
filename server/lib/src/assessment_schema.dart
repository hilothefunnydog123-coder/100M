import 'package:spotcheck_core/spotcheck_core.dart';

const _string = {'type': 'string'};
const _strings = {'type': 'array', 'items': _string};

/// JSON schema passed as `output_config.format`, so every response parses
/// into [ModelAssessment]. Property order is deliberate: the model assesses
/// photo quality and describes what it sees before naming conditions, and
/// writes the headline last.
final Map<String, Object?> assessmentSchema = _object({
  'image_quality': _object({
    'usable': {'type': 'boolean'},
    'issues': {
      'type': 'array',
      'items': {
        'type': 'string',
        'enum': [for (final i in PhotoIssue.values) i.id],
      },
    },
    'retake_advice': _string,
  }),
  'observations': _object({'summary': _string, 'features': _strings}),
  'possibilities': {
    'type': 'array',
    'items': _object({
      'name': _string,
      'medical_term': _string,
      'icd10': _string,
      'likelihood': {
        'type': 'string',
        'enum': [for (final l in Likelihood.values) l.id],
      },
      'description': _string,
      'supporting_features': _string,
      'serious': {'type': 'boolean'},
    }),
  },
  'red_flags': _strings,
  'urgency': {
    'type': 'string',
    'enum': [for (final u in Urgency.values) u.id],
  },
  'urgency_reason': _string,
  'care_setting': {
    'type': 'string',
    'enum': [for (final c in CareSetting.values) c.id],
  },
  'watch_for': _strings,
  'self_care': _strings,
  'doctor_questions': _strings,
  'confidence': {
    'type': 'string',
    'enum': [for (final c in Confidence.values) c.id],
  },
  'confidence_note': _string,
  'headline': _string,
});

/// Structured outputs require every object to list all of its properties as
/// required and to forbid additional properties.
Map<String, Object?> _object(Map<String, Object?> properties) => {
  'type': 'object',
  'properties': properties,
  'required': properties.keys.toList(),
  'additionalProperties': false,
};
