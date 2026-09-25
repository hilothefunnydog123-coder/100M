import 'package:spotcheck_core/spotcheck_core.dart';

/// A completed check as stored on the device.
class CheckRecord {
  const CheckRecord({
    required this.id,
    required this.createdAt,
    required this.site,
    required this.answers,
    required this.result,
    this.note = '',
    this.photoKeys = const [],
    this.followUpOf,
    this.recheckDue,
    this.doctorVerdict = '',
  });

  final String id;
  final DateTime createdAt;
  final BodySite site;
  final IntakeAnswers answers;
  final String note;
  final CheckResult result;

  /// Keys of the stored photos, in capture order.
  final List<String> photoKeys;

  /// The earlier check of the same spot, when this is a recheck.
  final String? followUpOf;

  /// When the person asked to be reminded to recheck the spot.
  final DateTime? recheckDue;

  /// What a clinician later concluded, entered by the person. With consent,
  /// confirmed outcomes are the best data for measuring accuracy.
  final String doctorVerdict;

  bool get tracking => recheckDue != null;

  CheckRecord copyWith({
    DateTime? Function()? recheckDue,
    String? doctorVerdict,
  }) => CheckRecord(
    id: id,
    createdAt: createdAt,
    site: site,
    answers: answers,
    result: result,
    note: note,
    photoKeys: photoKeys,
    followUpOf: followUpOf,
    recheckDue: recheckDue == null ? this.recheckDue : recheckDue(),
    doctorVerdict: doctorVerdict ?? this.doctorVerdict,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'created_at': createdAt.toUtc().toIso8601String(),
    'site': site.id,
    'answers': answers.toJson(),
    'note': note,
    'result': result.toJson(),
    'photo_keys': photoKeys,
    'follow_up_of': ?followUpOf,
    'recheck_due': ?recheckDue?.toUtc().toIso8601String(),
    'doctor_verdict': doctorVerdict,
  };

  static CheckRecord? tryParse(Object? json) {
    if (json is! Map<String, Object?>) return null;
    try {
      final site = BodySite.fromId(json['site'] as String?);
      if (site == null) return null;
      return CheckRecord(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        site: site,
        answers: IntakeAnswers.fromJson(json['answers']),
        note: json['note'] as String? ?? '',
        result: CheckResult.fromJson(json['result'] as Map<String, Object?>),
        photoKeys: [
          for (final k in (json['photo_keys'] as List? ?? const []))
            if (k is String) k,
        ],
        followUpOf: json['follow_up_of'] as String?,
        recheckDue: DateTime.tryParse(json['recheck_due'] as String? ?? ''),
        doctorVerdict: json['doctor_verdict'] as String? ?? '',
      );
    } on Object {
      // Skip a corrupt record rather than losing the whole history.
      return null;
    }
  }
}

/// App settings and the person's own profile.
class AppSettings {
  const AppSettings({
    required this.installId,
    this.onboarded = false,
    this.profile = const {},
    this.checksUsed = 0,
    this.pro = false,
    this.emergencyNumber = '911',
  });

  /// Random id sent with checks for rate limiting. Not tied to identity.
  final String installId;
  final bool onboarded;

  /// Answers to the "about you" questions, used when checking yourself.
  final Map<String, List<String>> profile;
  final int checksUsed;
  final bool pro;
  final String emergencyNumber;

  IntakeAnswers get profileAnswers => IntakeAnswers.fromJson(profile);

  bool get hasProfile => profileAnswers.isAnswered(Q.ageBand);

  AppSettings copyWith({
    bool? onboarded,
    IntakeAnswers? profile,
    int? checksUsed,
    bool? pro,
    String? emergencyNumber,
  }) => AppSettings(
    installId: installId,
    onboarded: onboarded ?? this.onboarded,
    profile: profile?.toJson() ?? this.profile,
    checksUsed: checksUsed ?? this.checksUsed,
    pro: pro ?? this.pro,
    emergencyNumber: emergencyNumber ?? this.emergencyNumber,
  );

  Map<String, Object?> toJson() => {
    'install_id': installId,
    'onboarded': onboarded,
    'profile': profile,
    'checks_used': checksUsed,
    'pro': pro,
    'emergency_number': emergencyNumber,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
    installId: json['install_id'] as String? ?? newId('inst'),
    onboarded: json['onboarded'] == true,
    profile: IntakeAnswers.fromJson(json['profile']).toJson(),
    checksUsed: (json['checks_used'] as num?)?.toInt() ?? 0,
    pro: json['pro'] == true,
    emergencyNumber: json['emergency_number'] as String? ?? '911',
  );
}
