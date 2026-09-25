import 'json.dart';
import 'trade.dart';
import 'units.dart';

/// One of the contractor's own prices, e.g. "Interior walls, 2 coats:
/// $2.10 per sq ft". Learned entries come from prices they typed over AI
/// drafts (see `PriceMemory`).
class PriceEntry {
  const PriceEntry({
    required this.id,
    required this.name,
    required this.unit,
    required this.unitPriceCents,
    this.learned = false,
    this.updatedAt,
  });

  static const maxNameLength = 100;

  final String id;
  final String name;
  final Unit unit;
  final int unitPriceCents;
  final bool learned;
  final DateTime? updatedAt;

  PriceEntry copyWith({
    String? name,
    Unit? unit,
    int? unitPriceCents,
    bool? learned,
    DateTime? updatedAt,
  }) => PriceEntry(
    id: id,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    unitPriceCents: unitPriceCents ?? this.unitPriceCents,
    learned: learned ?? this.learned,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'unit': unit.id,
    'unit_price_cents': unitPriceCents,
    'learned': learned,
    'updated_at': writeDate(updatedAt),
  };

  static PriceEntry? fromJson(Object? json) {
    final m = readMap(json);
    final id = readString(m['id'], max: 40);
    final name = readString(m['name'], max: maxNameLength);
    if (id.isEmpty || name.isEmpty) return null;
    return PriceEntry(
      id: id,
      name: name,
      unit: Unit.fromId(m['unit']),
      unitPriceCents: readInt(m['unit_price_cents'], max: 100000000),
      learned: readBool(m['learned']),
      updatedAt: readDate(m['updated_at']),
    );
  }
}

/// How a contractor prices work. Snapshotted into every quote so changing
/// your rates never changes a quote you already sent.
class Rates {
  const Rates({
    this.laborRateCents = 6500,
    this.materialMarkupPct = 20,
    this.minimumJobCents = 0,
    this.taxRatePct = 0,
    this.depositPct = 25,
    this.validDays = 30,
    this.roundPrices = true,
    this.priceList = const [],
  });

  factory Rates.forTrade(Trade trade) => Rates(
    laborRateCents: trade.defaultLaborRateCents,
    minimumJobCents: trade.defaultMinimumCents,
  );

  static const maxPriceList = 80;

  /// Billing rate per person-hour.
  final int laborRateCents;

  /// Added to material cost, e.g. 20 for 20%.
  final double materialMarkupPct;

  /// Totals below this are raised to it.
  final int minimumJobCents;

  /// Sales tax on the whole job, if the contractor charges it.
  final double taxRatePct;

  /// Share of the total due when the customer approves.
  final double depositPct;

  /// How long a quote stays valid.
  final int validDays;

  /// Round computed line prices to numbers people write ($2,480, not
  /// $2,477.63).
  final bool roundPrices;

  final List<PriceEntry> priceList;

  PriceEntry? priceEntry(String? id) {
    if (id == null) return null;
    for (final e in priceList) {
      if (e.id == id) return e;
    }
    return null;
  }

  Rates copyWith({
    int? laborRateCents,
    double? materialMarkupPct,
    int? minimumJobCents,
    double? taxRatePct,
    double? depositPct,
    int? validDays,
    bool? roundPrices,
    List<PriceEntry>? priceList,
  }) => Rates(
    laborRateCents: laborRateCents ?? this.laborRateCents,
    materialMarkupPct: materialMarkupPct ?? this.materialMarkupPct,
    minimumJobCents: minimumJobCents ?? this.minimumJobCents,
    taxRatePct: taxRatePct ?? this.taxRatePct,
    depositPct: depositPct ?? this.depositPct,
    validDays: validDays ?? this.validDays,
    roundPrices: roundPrices ?? this.roundPrices,
    priceList: priceList ?? this.priceList,
  );

  Map<String, Object?> toJson() => {
    'labor_rate_cents': laborRateCents,
    'material_markup_pct': materialMarkupPct,
    'minimum_job_cents': minimumJobCents,
    'tax_rate_pct': taxRatePct,
    'deposit_pct': depositPct,
    'valid_days': validDays,
    'round_prices': roundPrices,
    'price_list': [for (final e in priceList) e.toJson()],
  };

  factory Rates.fromJson(Object? json) {
    final m = readMap(json);
    const d = Rates();
    return Rates(
      laborRateCents: readInt(
        m['labor_rate_cents'],
        max: 100000,
        fallback: d.laborRateCents,
      ),
      materialMarkupPct: readDouble(
        m['material_markup_pct'],
        max: 300,
        fallback: d.materialMarkupPct,
      ),
      minimumJobCents: readInt(m['minimum_job_cents'], max: 100000000),
      taxRatePct: readDouble(m['tax_rate_pct'], max: 25),
      depositPct: readDouble(
        m['deposit_pct'],
        max: 100,
        fallback: d.depositPct,
      ),
      validDays: readInt(
        m['valid_days'],
        min: 1,
        max: 365,
        fallback: d.validDays,
      ),
      roundPrices: readBool(m['round_prices'], fallback: true),
      priceList: [
        for (final e in readList(m['price_list'], max: maxPriceList))
          ?PriceEntry.fromJson(e),
      ],
    );
  }
}
