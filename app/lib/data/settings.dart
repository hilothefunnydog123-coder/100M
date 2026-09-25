import 'package:jobwalk_core/jobwalk_core.dart';

/// Everything about this business and device that isn't a quote.
class AppSettings {
  const AppSettings({
    required this.installId,
    this.profile = const BusinessProfile(name: ''),
    this.rates = const Rates(),
    this.nextNumber = 1001,
    this.setupDone = false,
  });

  /// Random id for rate limiting; never personal information.
  final String installId;
  final BusinessProfile profile;
  final Rates rates;

  /// The number the next quote gets.
  final int nextNumber;
  final bool setupDone;

  AppSettings copyWith({
    BusinessProfile? profile,
    Rates? rates,
    int? nextNumber,
    bool? setupDone,
  }) => AppSettings(
    installId: installId,
    profile: profile ?? this.profile,
    rates: rates ?? this.rates,
    nextNumber: nextNumber ?? this.nextNumber,
    setupDone: setupDone ?? this.setupDone,
  );

  Map<String, Object?> toJson() => {
    'install_id': installId,
    'profile': profile.toJson(),
    'rates': rates.toJson(),
    'next_number': nextNumber,
    'setup_done': setupDone,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final id = json['install_id'];
    final next = json['next_number'];
    return AppSettings(
      installId: id is String && id.isNotEmpty ? id : newId('inst'),
      profile: BusinessProfile.fromJson(json['profile']),
      rates: Rates.fromJson(json['rates']),
      nextNumber: next is int && next > 0 ? next : 1001,
      setupDone: json['setup_done'] == true,
    );
  }
}
