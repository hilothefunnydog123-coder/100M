import 'json.dart';
import 'line_item.dart';
import 'quote.dart';
import 'units.dart';

/// The model's draft of a quote, parsed from structured output.
///
/// Parsing is defensive: values are clamped, unknown units and option ids
/// are dropped, and inconsistent options are collapsed so a line can never
/// be counted twice. Costs arrive in dollars and are stored in cents.
class AiDraft {
  const AiDraft({
    this.photosUsable = true,
    this.retakeAdvice = '',
    this.title = '',
    this.summary = '',
    this.observations = const [],
    this.measurements = const [],
    this.tiers = const [],
    this.items = const [],
    this.assumptions = const [],
    this.exclusions = const [],
    this.crewPeople = 0,
    this.crewDays = 0,
    this.customerMessage = '',
    this.confidence = Impact.medium,
    this.confidenceNote = '',
  });

  static const maxItems = 40;
  static const maxTiers = 3;
  static const maxAssumptions = 6;
  static const maxMeasurements = 12;

  final bool photosUsable;
  final String retakeAdvice;
  final String title;
  final String summary;
  final List<String> observations;
  final List<Measurement> measurements;
  final List<Tier> tiers;
  final List<LineItem> items;
  final List<Assumption> assumptions;
  final List<String> exclusions;
  final int crewPeople;
  final double crewDays;
  final String customerMessage;
  final Impact confidence;
  final String confidenceNote;

  /// A draft worth showing; otherwise ask for better photos.
  bool get isUsable => photosUsable && items.isNotEmpty;

  factory AiDraft.fromJson(Map<String, Object?> json) {
    final tiers = <Tier>[];
    for (final raw in readList(json['tiers'], max: 6)) {
      final t = Tier.fromJson(raw);
      if (t != null && tiers.every((x) => x.id != t.id)) tiers.add(t);
    }
    if (tiers.length > maxTiers) tiers.removeRange(maxTiers, tiers.length);
    final tierIds = {for (final t in tiers) t.id};

    final items = <LineItem>[];
    for (final raw in readList(json['items'], max: maxItems)) {
      final m = readMap(raw);
      final description = readString(
        m['description'],
        max: LineItem.maxDescription,
      );
      if (description.isEmpty) continue;
      var ids = {
        for (final id in readStrings(m['tiers'], maxItems: 6, maxLength: 20))
          if (tierIds.contains(id.toLowerCase())) id.toLowerCase(),
      };
      if (ids.length == tierIds.length) ids = {};
      final unit = Unit.fromId(m['unit']);
      final priceListId = readString(m['price_list_id'], max: 40);
      items.add(
        LineItem(
          id: 'l${items.length + 1}',
          description: description,
          detail: readString(m['detail'], max: LineItem.maxDetail),
          section: readString(m['section'], max: LineItem.maxSection),
          quantity: unit.isLumpSum
              ? 1
              : readDouble(
                  m['quantity'],
                  max: LineItem.maxQuantity,
                  fallback: 1,
                ),
          unit: unit,
          laborHours: readDouble(m['labor_hours'], max: LineItem.maxHours),
          materialCostCents: dollarsToCents(m['material_cost']),
          otherCostCents: dollarsToCents(m['other_cost']),
          priceListId: priceListId.isEmpty ? null : priceListId,
          tierIds: ids,
          basis: readString(m['basis'], max: LineItem.maxBasis),
          fromAi: true,
        ),
      );
    }

    final (cleanTiers, cleanItems) = _normalizeTiers(tiers, items);
    final crew = readMap(json['crew']);
    return AiDraft(
      photosUsable: readBool(json['photos_usable'], fallback: true),
      retakeAdvice: readString(json['retake_advice'], max: 400),
      title: readString(json['title'], max: 120),
      summary: readString(json['summary'], max: 1000),
      observations: readStrings(json['observations'], maxItems: 12),
      measurements: [
        for (final m in readList(json['measurements'], max: maxMeasurements))
          ?Measurement.fromJson(m),
      ],
      tiers: cleanTiers,
      items: cleanItems,
      assumptions: [
        for (final a in readList(json['assumptions'], max: maxAssumptions))
          ?Assumption.fromJson(a),
      ],
      exclusions: readStrings(json['exclusions'], maxItems: 12),
      crewPeople: readInt(crew['people'], max: 50),
      crewDays: readDouble(crew['days'], max: 365),
      customerMessage: readString(json['customer_message'], max: 800),
      confidence: Impact.fromId(json['confidence']),
      confidenceNote: readString(json['confidence_note'], max: 400),
    );
  }

  /// Options need at least two non-empty tiers and one recommendation at
  /// most. Otherwise the draft collapses to the single option the model
  /// preferred, keeping only that option's lines.
  static (List<Tier>, List<LineItem>) _normalizeTiers(
    List<Tier> tiers,
    List<LineItem> items,
  ) {
    final used = [
      for (final t in tiers)
        if (items.any((i) => i.inTier(t.id))) t,
    ];
    if (used.length >= 2) {
      final usedIds = {for (final t in used) t.id};
      final recommended = used.where((t) => t.recommended).firstOrNull;
      return (
        [for (final t in used) t.copyWith(recommended: t == recommended)],
        [
          for (final i in items)
            i.copyWith(
              tierIds: i.tierIds.length == usedIds.length
                  ? const {}
                  : i.tierIds.intersection(usedIds),
            ),
        ],
      );
    }
    if (tiers.isEmpty) return (const [], items);
    final keep =
        (used.where((t) => t.recommended).firstOrNull ??
                used.firstOrNull ??
                tiers.first)
            .id;
    return (
      const [],
      [
        for (final i in items)
          if (i.inTier(keep)) i.copyWith(tierIds: const {}),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'photos_usable': photosUsable,
    'retake_advice': retakeAdvice,
    'title': title,
    'summary': summary,
    'observations': observations,
    'measurements': [for (final m in measurements) m.toJson()],
    'tiers': [for (final t in tiers) t.toJson()],
    'items': [
      for (final i in items)
        {
          'section': i.section,
          'description': i.description,
          'detail': i.detail,
          'quantity': i.quantity,
          'unit': i.unit.id,
          'price_list_id': i.priceListId ?? '',
          'labor_hours': i.laborHours,
          'material_cost': i.materialCostCents / 100,
          'other_cost': i.otherCostCents / 100,
          'tiers': i.tierIds.toList(),
          'basis': i.basis,
        },
    ],
    'assumptions': [
      for (final a in assumptions) {'text': a.text, 'impact': a.impact.id},
    ],
    'exclusions': exclusions,
    'crew': {'people': crewPeople, 'days': crewDays},
    'customer_message': customerMessage,
    'confidence': confidence.id,
    'confidence_note': confidenceNote,
  };
}
