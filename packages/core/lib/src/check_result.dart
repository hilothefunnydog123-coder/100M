import 'urgency.dart';

/// How strongly the evidence points to a possibility.
enum Likelihood {
  high('high', 'Most likely'),
  moderate('moderate', 'Possible'),
  low('low', 'Less likely');

  const Likelihood(this.id, this.label);

  final String id;
  final String label;

  static Likelihood fromId(Object? id) =>
      values.firstWhere((v) => v.id == id, orElse: () => Likelihood.low);
}

enum Confidence {
  high('high', 'High'),
  moderate('moderate', 'Moderate'),
  low('low', 'Low');

  const Confidence(this.id, this.label);

  final String id;
  final String label;

  static Confidence fromId(Object? id) =>
      values.firstWhere((v) => v.id == id, orElse: () => Confidence.low);
}

/// Why a photo couldn't be assessed.
enum PhotoIssue {
  blurry('blurry', 'Blurry'),
  tooDark('too_dark', 'Too dark'),
  tooBright('too_bright', 'Too bright or glare'),
  tooFar('too_far', 'Too far away'),
  tooClose('too_close', 'Too close'),
  obstructed('obstructed', 'Something is in the way'),
  colorCast('color_cast', 'Colors look off'),
  filtered('filtered', 'Filtered or edited'),
  wrongSubject('wrong_subject', "Doesn't show the area");

  const PhotoIssue(this.id, this.label);

  final String id;
  final String label;

  static PhotoIssue? fromId(Object? id) {
    for (final v in values) {
      if (v.id == id) return v;
    }
    return null;
  }
}

enum CheckStatus {
  /// A full assessment is available.
  complete('complete'),

  /// The photos weren't good enough; the person should retake them.
  retake('retake'),

  /// The analysis couldn't be completed (for example a safety decline).
  declined('declined');

  const CheckStatus(this.id);

  final String id;

  static CheckStatus fromId(Object? id) =>
      values.firstWhere((v) => v.id == id, orElse: () => CheckStatus.declined);
}

class ImageQuality {
  const ImageQuality({
    required this.usable,
    this.issues = const [],
    this.retakeAdvice = '',
  });

  final bool usable;
  final List<PhotoIssue> issues;
  final String retakeAdvice;

  factory ImageQuality.fromJson(Map<String, Object?> json) => ImageQuality(
    usable: _bool(json, 'usable'),
    issues: [for (final i in _list(json, 'issues')) ?PhotoIssue.fromId(i)],
    retakeAdvice: _str(json, 'retake_advice', required: false),
  );

  Map<String, Object?> toJson() => {
    'usable': usable,
    'issues': [for (final i in issues) i.id],
    'retake_advice': retakeAdvice,
  };
}

class Possibility {
  const Possibility({
    required this.name,
    required this.likelihood,
    this.medicalTerm = '',
    this.icd10 = '',
    this.description = '',
    this.supportingFeatures = '',
    this.serious = false,
  });

  /// Everyday name, e.g. "Eczema".
  final String name;

  /// Clinical name, e.g. "Atopic dermatitis". May be empty.
  final String medicalTerm;

  /// ICD-10 code where one fits, e.g. "L20.9". Used for evaluation and
  /// doctor summaries, never shown as a diagnosis.
  final String icd10;

  final Likelihood likelihood;

  /// What the condition is, in one or two sentences.
  final String description;

  /// Which visible or reported features point to it.
  final String supportingFeatures;

  /// Whether this condition usually needs medical treatment.
  final bool serious;

  factory Possibility.fromJson(Map<String, Object?> json) => Possibility(
    name: _str(json, 'name'),
    medicalTerm: _str(json, 'medical_term', required: false),
    icd10: _str(json, 'icd10', required: false, maxLength: 12),
    likelihood: Likelihood.fromId(json['likelihood']),
    description: _str(json, 'description', required: false),
    supportingFeatures: _str(json, 'supporting_features', required: false),
    serious: json['serious'] == true,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'medical_term': medicalTerm,
    'icd10': icd10,
    'likelihood': likelihood.id,
    'description': description,
    'supporting_features': supportingFeatures,
    'serious': serious,
  };
}

/// The model's structured assessment, exactly as constrained by the output
/// schema (see the server's `assessment_schema.dart`).
class ModelAssessment {
  const ModelAssessment({
    required this.imageQuality,
    required this.urgency,
    required this.careSetting,
    this.headline = '',
    this.observationSummary = '',
    this.observedFeatures = const [],
    this.possibilities = const [],
    this.urgencyReason = '',
    this.redFlags = const [],
    this.watchFor = const [],
    this.selfCare = const [],
    this.doctorQuestions = const [],
    this.confidence = Confidence.low,
    this.confidenceNote = '',
  });

  static const maxPossibilities = 5;
  static const maxListItems = 8;

  final ImageQuality imageQuality;
  final String headline;
  final String observationSummary;
  final List<String> observedFeatures;
  final List<Possibility> possibilities;
  final Urgency urgency;
  final String urgencyReason;
  final CareSetting careSetting;
  final List<String> redFlags;
  final List<String> watchFor;
  final List<String> selfCare;
  final List<String> doctorQuestions;
  final Confidence confidence;
  final String confidenceNote;

  /// Parses and bounds model output. Throws [FormatException] when a field
  /// that safety depends on is missing or invalid.
  factory ModelAssessment.fromJson(Map<String, Object?> json) {
    final urgency = Urgency.fromId(json['urgency'] as String?);
    if (urgency == null) {
      throw FormatException('Invalid urgency: ${json['urgency']}');
    }
    final quality = json['image_quality'];
    if (quality is! Map<String, Object?>) {
      throw const FormatException('Missing image_quality');
    }
    final observations = json['observations'];
    final obs = observations is Map<String, Object?>
        ? observations
        : const <String, Object?>{};
    return ModelAssessment(
      imageQuality: ImageQuality.fromJson(quality),
      headline: _str(json, 'headline', required: false),
      observationSummary: _str(obs, 'summary', required: false),
      observedFeatures: _strings(obs, 'features'),
      possibilities: [
        for (final p in _list(json, 'possibilities').take(maxPossibilities))
          if (p is Map<String, Object?>) Possibility.fromJson(p),
      ],
      urgency: urgency,
      urgencyReason: _str(json, 'urgency_reason', required: false),
      careSetting:
          CareSetting.fromId(json['care_setting'] as String?) ??
          CareSetting.defaultFor(urgency),
      redFlags: _strings(json, 'red_flags'),
      watchFor: _strings(json, 'watch_for'),
      selfCare: _strings(json, 'self_care'),
      doctorQuestions: _strings(json, 'doctor_questions'),
      confidence: Confidence.fromId(json['confidence']),
      confidenceNote: _str(json, 'confidence_note', required: false),
    );
  }

  Map<String, Object?> toJson() => {
    'image_quality': imageQuality.toJson(),
    'headline': headline,
    'observations': {
      'summary': observationSummary,
      'features': observedFeatures,
    },
    'possibilities': [for (final p in possibilities) p.toJson()],
    'urgency': urgency.id,
    'urgency_reason': urgencyReason,
    'care_setting': careSetting.id,
    'red_flags': redFlags,
    'watch_for': watchFor,
    'self_care': selfCare,
    'doctor_questions': doctorQuestions,
    'confidence': confidence.id,
    'confidence_note': confidenceNote,
  };
}

/// A safety rule that fired, as shown to the person.
class SafetyNote {
  const SafetyNote({
    required this.ruleId,
    required this.urgency,
    required this.reason,
    this.action,
  });

  final String ruleId;
  final Urgency urgency;
  final String reason;
  final String? action;

  factory SafetyNote.fromJson(Map<String, Object?> json) => SafetyNote(
    ruleId: _str(json, 'rule_id'),
    urgency: Urgency.fromId(json['urgency'] as String?) ?? Urgency.soon,
    reason: _str(json, 'reason'),
    action: json['action'] as String?,
  );

  Map<String, Object?> toJson() => {
    'rule_id': ruleId,
    'urgency': urgency.id,
    'reason': reason,
    if (action != null) 'action': action,
  };
}

/// The final result of a check: the model's assessment merged with the
/// deterministic safety rules. This is what the app shows and stores.
class CheckResult {
  const CheckResult({
    required this.id,
    required this.status,
    required this.createdAt,
    this.urgency,
    this.careSetting,
    this.escalatedBySafetyRules = false,
    this.safetyNotes = const [],
    this.assessment,
    this.message = '',
    this.model = '',
    this.demo = false,
  });

  final String id;
  final CheckStatus status;
  final DateTime createdAt;

  /// Final urgency. Null only when the photos couldn't be assessed and no
  /// safety rule applied.
  final Urgency? urgency;

  final CareSetting? careSetting;

  /// True when a safety rule raised the urgency above the model's.
  final bool escalatedBySafetyRules;

  final List<SafetyNote> safetyNotes;

  /// Null when the check was declined.
  final ModelAssessment? assessment;

  /// Explanation for retake/declined results.
  final String message;

  /// Model that produced the assessment (for audit and evaluation).
  final String model;

  /// True for canned demo results, so they are never mistaken for real ones.
  final bool demo;

  factory CheckResult.fromJson(Map<String, Object?> json) {
    final assessment = json['assessment'];
    return CheckResult(
      id: _str(json, 'id'),
      status: CheckStatus.fromId(json['status']),
      createdAt:
          DateTime.tryParse(_str(json, 'created_at', required: false)) ??
          DateTime.now().toUtc(),
      urgency: Urgency.fromId(json['urgency'] as String?),
      careSetting: CareSetting.fromId(json['care_setting'] as String?),
      escalatedBySafetyRules: json['escalated_by_safety_rules'] == true,
      safetyNotes: [
        for (final n in _list(json, 'safety_notes'))
          if (n is Map<String, Object?>) SafetyNote.fromJson(n),
      ],
      assessment: assessment is Map<String, Object?>
          ? ModelAssessment.fromJson(assessment)
          : null,
      message: _str(json, 'message', required: false),
      model: _str(json, 'model', required: false),
      demo: json['demo'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'status': status.id,
    'created_at': createdAt.toUtc().toIso8601String(),
    if (urgency != null) 'urgency': urgency!.id,
    if (careSetting != null) 'care_setting': careSetting!.id,
    'escalated_by_safety_rules': escalatedBySafetyRules,
    'safety_notes': [for (final n in safetyNotes) n.toJson()],
    if (assessment != null) 'assessment': assessment!.toJson(),
    'message': message,
    'model': model,
    'demo': demo,
  };
}

// ---- Bounded JSON helpers ------------------------------------------------

const _maxString = 800;

String _str(
  Map<String, Object?> json,
  String key, {
  bool required = true,
  int maxLength = _maxString,
}) {
  final v = json[key];
  if (v is String) {
    final t = v.trim();
    return t.length > maxLength ? '${t.substring(0, maxLength - 1)}…' : t;
  }
  if (required) throw FormatException('Missing string field "$key"');
  return '';
}

bool _bool(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v is bool) return v;
  throw FormatException('Missing boolean field "$key"');
}

List<Object?> _list(Map<String, Object?> json, String key) {
  final v = json[key];
  return v is List ? v.cast<Object?>() : const [];
}

List<String> _strings(Map<String, Object?> json, String key) => [
  for (final v in _list(json, key).take(ModelAssessment.maxListItems))
    if (v is String && v.trim().isNotEmpty)
      v.trim().length > _maxString
          ? '${v.trim().substring(0, _maxString - 1)}…'
          : v.trim(),
];
