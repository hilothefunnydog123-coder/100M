import 'line_item.dart';
import 'quote.dart';
import 'rates.dart';

/// Learns a contractor's prices from what they actually send.
///
/// When they re-price an AI line (type a total or a unit price), that
/// becomes a learned price-list entry. The next draft sees it in the
/// prompt, and the line is priced with their number instead of an estimate.
/// The price list they maintain by hand always wins over learned entries.
abstract final class PriceMemory {
  static const maxLearned = 40;

  static Rates learn(Rates rates, Quote sent, {required DateTime now}) {
    final list = [...rates.priceList];
    for (final item in sent.items) {
      final perUnit = _pricePerUnit(item);
      if (perUnit == null) continue;
      final key = _key(item.description);
      final manual = list.any(
        (e) => !e.learned && e.unit == item.unit && _key(e.name) == key,
      );
      if (manual) continue;
      final existing = list.indexWhere(
        (e) => e.learned && e.unit == item.unit && _key(e.name) == key,
      );
      if (existing >= 0) {
        list[existing] = list[existing].copyWith(
          unitPriceCents: perUnit,
          updatedAt: now,
        );
      } else {
        list.add(
          PriceEntry(
            id: 'learned_${_hash(key)}_${item.unit.id}',
            name: item.description,
            unit: item.unit,
            unitPriceCents: perUnit,
            learned: true,
            updatedAt: now,
          ),
        );
      }
    }

    // Keep the most recent learned entries within the cap.
    final learned = list.where((e) => e.learned).toList()
      ..sort(
        (a, b) =>
            (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)),
      );
    final keep = learned.take(maxLearned).toSet();
    final trimmed = [
      for (final e in list)
        if (!e.learned || keep.contains(e)) e,
    ].take(Rates.maxPriceList).toList();
    return rates.copyWith(priceList: trimmed);
  }

  /// The contractor's own price per unit for an AI line they re-priced.
  static int? _pricePerUnit(LineItem item) {
    if (!item.fromAi || item.unit.isLumpSum || item.quantity <= 0) return null;
    final override = item.priceOverrideCents;
    if (override != null) return (override / item.quantity).round();
    // A typed unit price, not one that came from the price list.
    if (item.unitPriceCents != null && item.priceListId == null) {
      return item.unitPriceCents;
    }
    return null;
  }

  static String _key(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  /// FNV-1a, so the same description always gets the same id.
  static String _hash(String key) {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
