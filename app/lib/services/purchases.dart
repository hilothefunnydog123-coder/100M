/// A subscription option shown on the paywall.
class Plan {
  const Plan({
    required this.id,
    required this.title,
    required this.price,
    required this.period,
    required this.perWeek,
    this.trialDays = 0,
    this.badge,
  });

  final String id;
  final String title;
  final String price;
  final String period;
  final String perWeek;
  final int trialDays;
  final String? badge;
}

/// Store purchases. Production builds should implement this with RevenueCat
/// (`purchases_flutter`) or StoreKit/Play Billing, verifying entitlements
/// server-side; see docs/LAUNCH.md.
abstract interface class PurchasesService {
  List<Plan> get plans;

  /// True while purchases are simulated (development builds).
  bool get simulated;

  Future<bool> purchase(Plan plan);
  Future<bool> restore();
}

/// Simulates purchases so the full flow can be built and tested before
/// store products exist. Never ship this to the stores.
class SimulatedPurchasesService implements PurchasesService {
  SimulatedPurchasesService({required this.onUnlock});

  final Future<void> Function() onUnlock;

  @override
  bool get simulated => true;

  @override
  List<Plan> get plans => const [
    Plan(
      id: 'pro_annual',
      title: 'Yearly',
      price: r'$49.99',
      period: 'year',
      perWeek: r'$0.96/week',
      trialDays: 7,
      badge: 'Save 58%',
    ),
    Plan(
      id: 'pro_monthly',
      title: 'Monthly',
      price: r'$9.99',
      period: 'month',
      perWeek: r'$2.31/week',
    ),
  ];

  @override
  Future<bool> purchase(Plan plan) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await onUnlock();
    return true;
  }

  @override
  Future<bool> restore() async => false;
}
