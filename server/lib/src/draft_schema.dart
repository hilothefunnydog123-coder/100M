import 'package:jobwalk_core/jobwalk_core.dart';

const _string = {'type': 'string'};
const _strings = {'type': 'array', 'items': _string};
const _number = {'type': 'number'};
const _level = {
  'type': 'string',
  'enum': ['high', 'medium', 'low'],
};

/// JSON schema passed as `output_config.format`, so every response parses
/// into [AiDraft]. Property order is deliberate: the model looks and
/// measures before it scopes, reasons about each line before its numbers,
/// and names the job last.
final Map<String, Object?> draftSchema = _object({
  'photos_usable': {'type': 'boolean'},
  'retake_advice': _string,
  'observations': _strings,
  'measurements': {
    'type': 'array',
    'items': _object({
      'name': _string,
      'how': _string,
      'quantity': _number,
      'unit': _unit,
      'confidence': _level,
    }),
  },
  'tiers': {
    'type': 'array',
    'items': _object({
      'id': _string,
      'name': _string,
      'summary': _string,
      'recommended': {'type': 'boolean'},
    }),
  },
  'items': {
    'type': 'array',
    'items': _object({
      'section': _string,
      'description': _string,
      'detail': _string,
      'basis': _string,
      'quantity': _number,
      'unit': _unit,
      'price_list_id': _string,
      'labor_hours': _number,
      'material_cost': _number,
      'other_cost': _number,
      'tiers': _strings,
    }),
  },
  'assumptions': {
    'type': 'array',
    'items': _object({'text': _string, 'impact': _level}),
  },
  'exclusions': _strings,
  'crew': _object({
    'people': {'type': 'integer'},
    'days': _number,
  }),
  'title': _string,
  'summary': _string,
  'customer_message': _string,
  'confidence': _level,
  'confidence_note': _string,
});

final _unit = {
  'type': 'string',
  'enum': [for (final u in Unit.values) u.id],
};

/// Structured outputs require every object to list all of its properties as
/// required and to forbid additional properties.
Map<String, Object?> _object(Map<String, Object?> properties) => {
  'type': 'object',
  'properties': properties,
  'required': properties.keys.toList(),
  'additionalProperties': false,
};
