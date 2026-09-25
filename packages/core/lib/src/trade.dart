/// The trades Jobwalk quotes for. Defaults are typical 2026 US billing
/// rates for small crews; every contractor sets their own in settings.
enum Trade {
  painting('painting', 'Painting', 6000, 50000),
  pressureWashing('pressure_washing', 'Pressure washing', 6500, 20000),
  fencing('fencing', 'Fencing', 6000, 50000),
  landscaping('landscaping', 'Landscaping', 5500, 25000),
  decks('decks', 'Decks', 6500, 50000),
  roofing('roofing', 'Roofing', 7500, 40000),
  gutters('gutters', 'Gutters', 6500, 15000),
  drywall('drywall', 'Drywall', 6500, 25000),
  flooring('flooring', 'Flooring', 6000, 50000),
  concrete('concrete', 'Concrete & pavers', 7000, 75000),
  handyman('handyman', 'Handyman', 8000, 15000),
  treeService('tree_service', 'Tree service', 8500, 30000),
  junkRemoval('junk_removal', 'Junk removal', 6000, 10000),
  cleaning('cleaning', 'Cleaning', 4500, 12000),
  other('other', 'Other', 6500, 20000);

  const Trade(
    this.id,
    this.label,
    this.defaultLaborRateCents,
    this.defaultMinimumCents,
  );

  final String id;
  final String label;

  /// Billing rate per person-hour.
  final int defaultLaborRateCents;

  /// Smallest job worth the drive.
  final int defaultMinimumCents;

  static Trade fromId(Object? id) =>
      values.firstWhere((t) => t.id == id, orElse: () => Trade.other);
}
