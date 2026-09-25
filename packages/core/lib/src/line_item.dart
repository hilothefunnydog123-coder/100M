import 'json.dart';
import 'units.dart';

/// How a line's price is set. See `Pricing.line`.
enum PricingMode {
  /// Labor hours at the contractor's rate, plus marked-up materials, plus
  /// pass-through costs. What AI drafts use by default.
  cost,

  /// Quantity times an all-in price per unit (from the price list, or typed
  /// by the contractor).
  unitRate,

  /// The contractor typed the line's total.
  fixed,
}

/// One line on a quote.
class LineItem {
  const LineItem({
    required this.id,
    required this.description,
    this.detail = '',
    this.section = '',
    this.quantity = 1,
    this.unit = Unit.lot,
    this.laborHours = 0,
    this.materialCostCents = 0,
    this.otherCostCents = 0,
    this.unitPriceCents,
    this.priceOverrideCents,
    this.priceListId,
    this.tierIds = const {},
    this.basis = '',
    this.fromAi = false,
  });

  static const maxDescription = 120;
  static const maxDetail = 240;
  static const maxSection = 40;
  static const maxBasis = 600;
  static const maxQuantity = 1000000.0;
  static const maxHours = 5000.0;
  static const maxCostCents = 100000000;

  final String id;

  /// What the customer is paying for: "Paint walls, 2 coats".
  final String description;

  /// Optional specifics: "Living room and hall, eggshell".
  final String detail;

  /// Groups lines on the quote: "Prep", "Walls", "Trim".
  final String section;

  final double quantity;
  final Unit unit;

  /// Total person-hours for the line.
  final double laborHours;

  /// What the contractor pays for materials, before markup.
  final int materialCostCents;

  /// Passed through at cost: disposal, rentals, permits, subcontractors.
  final int otherCostCents;

  /// All-in price per unit, used instead of costs when set.
  final int? unitPriceCents;

  /// The line's total as typed by the contractor. Wins over everything.
  final int? priceOverrideCents;

  /// The price-list entry that priced this line, if any.
  final String? priceListId;

  /// Options (tiers) this line belongs to. Empty means every option.
  final Set<String> tierIds;

  /// How the AI arrived at the numbers. Shown to the contractor only.
  final String basis;

  final bool fromAi;

  PricingMode get mode => priceOverrideCents != null
      ? PricingMode.fixed
      : unitPriceCents != null
      ? PricingMode.unitRate
      : PricingMode.cost;

  bool inTier(String? tierId) =>
      tierId == null || tierIds.isEmpty || tierIds.contains(tierId);

  /// Changes the quantity and scales every amount with it, so the price per
  /// unit holds: correcting a measurement corrects the price.
  LineItem withQuantity(double value) {
    final q = value.clamp(0, maxQuantity).toDouble();
    if (quantity <= 0 || unit.isLumpSum) return _copy(quantity: q);
    final f = q / quantity;
    return _copy(
      quantity: q,
      laborHours: (laborHours * f).clamp(0, maxHours).toDouble(),
      materialCostCents: (materialCostCents * f).round(),
      otherCostCents: (otherCostCents * f).round(),
      priceOverrideCents: priceOverrideCents == null
          ? null
          : (priceOverrideCents! * f).round(),
    );
  }

  /// Sets the line's total, as typed by the contractor.
  LineItem withTotal(int cents) =>
      _copy(priceOverrideCents: cents.clamp(0, maxCostCents));

  /// Drops a typed total, going back to the unit rate or the costs.
  LineItem withoutOverride() => _copy(priceOverrideCents: null);

  /// Prices the line at an all-in rate per unit.
  LineItem withUnitPrice(int cents, {String? priceListId}) => _copy(
    unitPriceCents: cents.clamp(0, maxCostCents),
    priceOverrideCents: null,
    priceListId: priceListId,
  );

  /// Prices the line from hours and costs again.
  LineItem withCosts({
    double? laborHours,
    int? materialCostCents,
    int? otherCostCents,
  }) => _copy(
    laborHours: (laborHours ?? this.laborHours).clamp(0, maxHours).toDouble(),
    materialCostCents: (materialCostCents ?? this.materialCostCents).clamp(
      0,
      maxCostCents,
    ),
    otherCostCents: (otherCostCents ?? this.otherCostCents).clamp(
      0,
      maxCostCents,
    ),
    unitPriceCents: null,
    priceOverrideCents: null,
    priceListId: null,
  );

  LineItem copyWith({
    String? description,
    String? detail,
    String? section,
    Unit? unit,
    Set<String>? tierIds,
  }) => _copy(
    description: description,
    detail: detail,
    section: section,
    unit: unit,
    tierIds: tierIds,
  );

  static const _keep = Object();

  LineItem _copy({
    String? description,
    String? detail,
    String? section,
    double? quantity,
    Unit? unit,
    double? laborHours,
    int? materialCostCents,
    int? otherCostCents,
    Object? unitPriceCents = _keep,
    Object? priceOverrideCents = _keep,
    Object? priceListId = _keep,
    Set<String>? tierIds,
  }) => LineItem(
    id: id,
    description: description ?? this.description,
    detail: detail ?? this.detail,
    section: section ?? this.section,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    laborHours: laborHours ?? this.laborHours,
    materialCostCents: materialCostCents ?? this.materialCostCents,
    otherCostCents: otherCostCents ?? this.otherCostCents,
    unitPriceCents: identical(unitPriceCents, _keep)
        ? this.unitPriceCents
        : unitPriceCents as int?,
    priceOverrideCents: identical(priceOverrideCents, _keep)
        ? this.priceOverrideCents
        : priceOverrideCents as int?,
    priceListId: identical(priceListId, _keep)
        ? this.priceListId
        : priceListId as String?,
    tierIds: tierIds ?? this.tierIds,
    basis: basis,
    fromAi: fromAi,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'description': description,
    'detail': detail,
    'section': section,
    'quantity': quantity,
    'unit': unit.id,
    'labor_hours': laborHours,
    'material_cost_cents': materialCostCents,
    'other_cost_cents': otherCostCents,
    'unit_price_cents': unitPriceCents,
    'price_override_cents': priceOverrideCents,
    'price_list_id': priceListId,
    'tiers': tierIds.toList(),
    'basis': basis,
    'from_ai': fromAi,
  };

  static LineItem? fromJson(Object? json) {
    final m = readMap(json);
    final id = readString(m['id'], max: 40);
    final description = readString(m['description'], max: maxDescription);
    if (id.isEmpty || description.isEmpty) return null;
    int? optionalCents(Object? v) =>
        v is num ? readInt(v, max: maxCostCents) : null;
    final priceListId = readString(m['price_list_id'], max: 40);
    return LineItem(
      id: id,
      description: description,
      detail: readString(m['detail'], max: maxDetail),
      section: readString(m['section'], max: maxSection),
      quantity: readDouble(m['quantity'], max: maxQuantity, fallback: 1),
      unit: Unit.fromId(m['unit']),
      laborHours: readDouble(m['labor_hours'], max: maxHours),
      materialCostCents: readInt(m['material_cost_cents'], max: maxCostCents),
      otherCostCents: readInt(m['other_cost_cents'], max: maxCostCents),
      unitPriceCents: optionalCents(m['unit_price_cents']),
      priceOverrideCents: optionalCents(m['price_override_cents']),
      priceListId: priceListId.isEmpty ? null : priceListId,
      tierIds: {...readStrings(m['tiers'], maxItems: 3, maxLength: 20)},
      basis: readString(m['basis'], max: maxBasis),
      fromAi: readBool(m['from_ai']),
    );
  }
}

/// Puts lines of the same section together, sections in order of first
/// appearance and lines in their original order within a section.
List<T> groupBySection<T>(Iterable<T> items, String Function(T) sectionOf) {
  final buckets = <String, List<T>>{};
  for (final item in items) {
    (buckets[sectionOf(item)] ??= []).add(item);
  }
  return [for (final bucket in buckets.values) ...bucket];
}
