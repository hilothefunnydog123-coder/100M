import 'dart:convert';

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

/// A compact rendering of a JSON schema for prompts, such as
/// `{"name": string, "tags": [string], "level": "high"|"low"}`. For providers
/// without structured outputs; it is well under half the size of the schema.
String schemaShape(Map<String, Object?> schema) {
  if (schema['enum'] case final List<Object?> values) {
    return values.map(jsonEncode).join('|');
  }
  switch (schema['type']) {
    case 'object':
      final properties = schema['properties']! as Map<String, Object?>;
      final fields = [
        for (final MapEntry(:key, :value) in properties.entries)
          '${jsonEncode(key)}: ${schemaShape(value! as Map<String, Object?>)}',
      ];
      return '{${fields.join(', ')}}';
    case 'array':
      return '[${schemaShape(schema['items']! as Map<String, Object?>)}]';
    case final type:
      return '$type';
  }
}

/// Parses a model's JSON answer into a draft. JSON mode (Groq) guarantees
/// JSON but not our schema, so an answer missing any top-level field is
/// malformed rather than an empty draft. Structured outputs always pass.
AiDraft parseDraftAnswer(String text) {
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Output is not a JSON object.');
  }
  final missing = [
    for (final key in draftSchema['required']! as List<Object?>)
      if (!decoded.containsKey(key)) '$key',
  ];
  if (missing.isNotEmpty) {
    throw FormatException('Output is missing ${missing.join(', ')}.');
  }
  return AiDraft.fromJson(decoded);
}
