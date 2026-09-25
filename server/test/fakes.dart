import 'dart:convert';
import 'dart:typed_data';

import 'package:spotcheck_core/spotcheck_core.dart';
import 'package:spotcheck_server/spotcheck_server.dart';

final jpegBytes = Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, //
]);

/// Records requests and replies with queued responses (or errors).
class FakeMessagesApi implements MessagesApi {
  FakeMessagesApi(this.responses);

  /// Each entry is a [ClaudeMessage] to return or an exception to throw.
  final List<Object> responses;
  final requests = <Map<String, Object?>>[];
  final betaHeaders = <List<String>>[];

  @override
  Future<ClaudeMessage> createMessage(
    Map<String, Object?> body, {
    List<String> betas = const [],
  }) async {
    requests.add(body);
    betaHeaders.add(betas);
    if (responses.isEmpty) throw StateError('No fake response queued.');
    final next = responses.removeAt(0);
    if (next is ClaudeMessage) return next;
    throw next;
  }
}

ClaudeMessage message({
  Object? assessment,
  String? rawText,
  String stopReason = 'end_turn',
  String model = 'claude-opus-5-5',
  List<Map<String, Object?>> extraBlocks = const [],
}) => ClaudeMessage({
  'id': 'msg_test',
  'type': 'message',
  'role': 'assistant',
  'model': model,
  'stop_reason': stopReason,
  'content': [
    {'type': 'thinking', 'thinking': '', 'signature': 'sig'},
    ...extraBlocks,
    if (rawText != null || assessment != null)
      {'type': 'text', 'text': rawText ?? jsonEncode(assessment)},
  ],
  'usage': {
    'input_tokens': 1200,
    'output_tokens': 900,
    'cache_read_input_tokens': 2400,
    'cache_creation_input_tokens': 0,
  },
});

ClaudeMessage refusal() => ClaudeMessage({
  'id': 'msg_refused',
  'model': 'claude-opus-5-5',
  'stop_reason': 'refusal',
  'stop_details': {'type': 'refusal', 'category': null},
  'content': <Object?>[],
  'usage': {'input_tokens': 0, 'output_tokens': 0},
});

Map<String, Object?> assessmentJson({
  String urgency = 'self_care',
  String careSetting = 'self_care',
  bool usable = true,
  List<Map<String, Object?>>? possibilities,
  String confidence = 'moderate',
  List<String> redFlags = const [],
}) => {
  'image_quality': {
    'usable': usable,
    'issues': usable ? <String>[] : ['blurry'],
    'retake_advice': usable ? '' : 'Hold the phone steady and tap to focus.',
  },
  'observations': {
    'summary': 'A dry, scaly patch.',
    'features': ['Fine scale'],
  },
  'possibilities':
      possibilities ??
      [
        {
          'name': 'Eczema',
          'medical_term': 'Atopic dermatitis',
          'icd10': 'L20.9',
          'likelihood': 'high',
          'description': 'Dry, itchy skin.',
          'supporting_features': 'Scale and itch.',
          'serious': false,
        },
      ],
  'red_flags': redFlags,
  'urgency': urgency,
  'urgency_reason': 'Nothing concerning.',
  'care_setting': careSetting,
  'watch_for': ['Spreading redness'],
  'self_care': ['Moisturize twice a day'],
  'doctor_questions': ['Is this eczema?'],
  'confidence': confidence,
  'confidence_note': 'Clear photo.',
  'headline': 'Looks like eczema.',
};

Map<String, Object?> possibility(
  String name,
  String icd10,
  String likelihood, {
  bool serious = false,
}) => {
  'name': name,
  'medical_term': name,
  'icd10': icd10,
  'likelihood': likelihood,
  'description': '',
  'supporting_features': '',
  'serious': serious,
};

CheckRequest checkRequest({
  BodySite site = BodySite.arm,
  Map<String, List<String>> answers = const {
    'skin_kind': ['rash'],
  },
  String note = '',
  int photos = 1,
}) => CheckRequest(
  site: site,
  answers: IntakeAnswers.fromJson(answers),
  note: note,
  photos: [
    for (var i = 0; i < photos; i++)
      CheckPhoto(
        bytes: jpegBytes,
        mediaType: 'image/jpeg',
        kind: i == 0 ? PhotoKind.closeUp : PhotoKind.context,
      ),
  ],
);
