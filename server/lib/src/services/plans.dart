/// What each plan includes. Prices live in Stripe; this is what the server
/// enforces.
class PlanRules {
  const PlanRules({
    this.trialDrafts = 25,
    this.monthlyDraftCap = 500,
    this.maxUsers = const {'trial': 3, 'pro': 3, 'crew': 15},
  });

  /// AI drafts a new business gets before paying. Only usable drafts count.
  final int trialDrafts;

  /// Fair-use ceiling on paid plans, per rolling 30 days, to bound AI cost.
  final int monthlyDraftCap;
  final Map<String, int> maxUsers;

  int usersFor(String plan) => maxUsers[plan] ?? 1;
}

/// A business's subscription as stored, with the rules applied.
class BusinessPlan {
  const BusinessPlan({
    required this.plan,
    required this.status,
    required this.trialDraftsUsed,
    required this.rules,
  });

  factory BusinessPlan.fromRow(Map<String, dynamic> row, PlanRules rules) =>
      BusinessPlan(
        plan: row['plan'] as String,
        status: row['plan_status'] as String,
        trialDraftsUsed: row['trial_drafts_used'] as int,
        rules: rules,
      );

  /// `trial`, `pro`, or `crew`.
  final String plan;

  /// Stripe's subscription status, or `trialing` for the free trial.
  final String status;
  final int trialDraftsUsed;
  final PlanRules rules;

  static const _goodStanding = {'active', 'trialing', 'past_due'};

  /// Paying and in good standing. `past_due` keeps access while Stripe
  /// retries the card.
  bool get paid => plan != 'trial' && _goodStanding.contains(status);

  /// The plan whose limits apply: a lapsed subscription falls back to the
  /// free trial's.
  String get effectivePlan => paid ? plan : 'trial';

  int get trialDraftsLeft =>
      (rules.trialDrafts - trialDraftsUsed).clamp(0, rules.trialDrafts);

  bool get canDraft => paid || trialDraftsLeft > 0;

  int get maxUsers => rules.usersFor(effectivePlan);

  Map<String, Object?> toJson() => {
    'id': plan,
    'status': status,
    'paid': paid,
    'trial_drafts_included': rules.trialDrafts,
    'trial_drafts_used': trialDraftsUsed,
    'trial_drafts_left': paid ? null : trialDraftsLeft,
    'max_users': maxUsers,
  };
}
