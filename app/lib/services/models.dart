import 'package:jobwalk_core/jobwalk_core.dart';

Map<String, Object?> _map(Object? v) =>
    v is Map ? v.cast<String, Object?>() : const {};

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

String _str(Object? v) => v is String ? v : '';

/// The signed-in person.
class User {
  const User({
    required this.id,
    required this.email,
    this.name = '',
    this.role = 'owner',
    this.emailNotifications = true,
  });

  final String id;
  final String email;
  final String name;

  /// `owner` or `member`.
  final String role;
  final bool emailNotifications;

  bool get isOwner => role == 'owner';

  factory User.fromJson(Object? json) {
    final m = _map(json);
    return User(
      id: _str(m['id']),
      email: _str(m['email']),
      name: _str(m['name']),
      role: m['role'] == 'member' ? 'member' : 'owner',
      emailNotifications: m['email_notifications'] != false,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'role': role,
    'email_notifications': emailNotifications,
  };
}

/// The business's subscription and what it allows.
class Plan {
  const Plan({
    this.id = 'trial',
    this.status = 'trialing',
    this.paid = false,
    this.trialDraftsIncluded = 25,
    this.trialDraftsLeft,
    this.maxUsers = 3,
  });

  /// `trial`, `pro`, or `crew`.
  final String id;
  final String status;
  final bool paid;
  final int trialDraftsIncluded;

  /// Null on paid plans.
  final int? trialDraftsLeft;
  final int maxUsers;

  String get label => switch (id) {
    'pro' => 'Pro',
    'crew' => 'Crew',
    _ => 'Free trial',
  };

  factory Plan.fromJson(Object? json) {
    final m = _map(json);
    final left = m['trial_drafts_left'];
    return Plan(
      id: _str(m['id']).isEmpty ? 'trial' : _str(m['id']),
      status: _str(m['status']),
      paid: m['paid'] == true,
      trialDraftsIncluded: _int(m['trial_drafts_included'], 25),
      trialDraftsLeft: left is num ? left.toInt() : null,
      maxUsers: _int(m['max_users'], 3),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'status': status,
    'paid': paid,
    'trial_drafts_included': trialDraftsIncluded,
    'trial_drafts_left': trialDraftsLeft,
    'max_users': maxUsers,
  };
}

class Business {
  const Business({
    required this.id,
    required this.profile,
    required this.rates,
    this.setupComplete = false,
    this.plan = const Plan(),
    this.paymentsConnected = false,
    this.paymentsReady = false,
  });

  final String id;
  final BusinessProfile profile;
  final Rates rates;
  final bool setupComplete;
  final Plan plan;
  final bool paymentsConnected;
  final bool paymentsReady;

  factory Business.fromJson(Object? json) {
    final m = _map(json);
    final payments = _map(m['payments']);
    return Business(
      id: _str(m['id']),
      profile: BusinessProfile.fromJson(m['profile']),
      rates: Rates.fromJson(m['rates']),
      setupComplete: m['setup_complete'] == true,
      plan: Plan.fromJson(m['plan']),
      paymentsConnected: payments['connected'] == true,
      paymentsReady: payments['ready'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'profile': profile.toJson(),
    'rates': rates.toJson(),
    'setup_complete': setupComplete,
    'plan': plan.toJson(),
    'payments': {'connected': paymentsConnected, 'ready': paymentsReady},
  };
}

/// `GET /v1/me`.
class Account {
  const Account({required this.user, required this.business});

  final User user;
  final Business business;

  factory Account.fromJson(Object? json) {
    final m = _map(json);
    return Account(
      user: User.fromJson(m['user']),
      business: Business.fromJson(m['business']),
    );
  }

  Map<String, Object?> toJson() => {
    'user': user.toJson(),
    'business': business.toJson(),
  };
}

class TeamMember {
  const TeamMember({
    required this.id,
    required this.email,
    this.name = '',
    this.role = 'member',
    this.you = false,
  });

  final String id;
  final String email;
  final String name;
  final String role;
  final bool you;

  factory TeamMember.fromJson(Object? json) {
    final m = _map(json);
    return TeamMember(
      id: _str(m['id']),
      email: _str(m['email']),
      name: _str(m['name']),
      role: _str(m['role']),
      you: m['you'] == true,
    );
  }
}

/// Card deposits through Stripe Connect.
class Payments {
  const Payments({
    this.enabled = false,
    this.connected = false,
    this.ready = false,
    this.feeDescription = '',
  });

  /// The server has Stripe configured.
  final bool enabled;
  final bool connected;
  final bool ready;
  final String feeDescription;

  factory Payments.fromJson(Object? json) {
    final m = _map(json);
    return Payments(
      enabled: m['enabled'] == true,
      connected: m['connected'] == true,
      ready: m['ready'] == true,
      feeDescription: _str(_map(m['fee'])['description']),
    );
  }
}

/// A quote as the server has it.
class SyncedQuote {
  const SyncedQuote({
    required this.id,
    required this.version,
    this.deleted = false,
    this.quote,
    this.depositPaidCents,
  });

  final String id;
  final int version;
  final bool deleted;

  /// Null for deleted quotes.
  final Quote? quote;

  /// Set once the customer paid the deposit by card.
  final int? depositPaidCents;

  factory SyncedQuote.fromJson(Object? json) {
    final m = _map(json);
    final deposit = _map(m['deposit']);
    return SyncedQuote(
      id: _str(m['id']),
      version: _int(m['version']),
      deleted: m['deleted'] == true,
      quote: Quote.fromJson(m['quote']),
      depositPaidCents: deposit['status'] == 'paid'
          ? _int(deposit['paid_cents'])
          : null,
    );
  }
}

class SyncPage {
  const SyncPage({
    required this.items,
    required this.cursor,
    this.more = false,
  });

  final List<SyncedQuote> items;
  final int cursor;
  final bool more;
}
