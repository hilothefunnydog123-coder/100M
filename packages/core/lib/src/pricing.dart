import 'line_item.dart';
import 'money.dart';
import 'rates.dart';

/// Totals for one option of a quote. Labor and material figures are for the
/// contractor; customers only see prices.
class QuoteTotals {
  const QuoteTotals({
    required this.subtotalCents,
    required this.minimumAdjustmentCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.depositCents,
    required this.laborHours,
    required this.materialCostCents,
    required this.lineCount,
  });

  final int subtotalCents;

  /// Added when the subtotal is under the contractor's minimum job.
  final int minimumAdjustmentCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int depositCents;
  final double laborHours;
  final int materialCostCents;
  final int lineCount;
}

/// All money math. The model never computes a price or a total: it
/// estimates quantities, hours, and costs, and this turns them into prices
/// with the contractor's rates, deterministically and in integer cents.
abstract final class Pricing {
  /// The customer's price for one line.
  static int line(LineItem item, Rates rates) {
    final override = item.priceOverrideCents;
    if (override != null) return override;
    final unitPrice = item.unitPriceCents;
    final raw = unitPrice != null
        ? (item.quantity * unitPrice).round()
        : costBased(item, rates);
    return rates.roundPrices ? Money.roundNice(raw) : raw;
  }

  /// Labor at the contractor's rate, materials with their markup, and
  /// pass-through costs at cost.
  static int costBased(LineItem item, Rates rates) =>
      (item.laborHours * rates.laborRateCents).round() +
      (item.materialCostCents * (1 + rates.materialMarkupPct / 100)).round() +
      item.otherCostCents;

  /// Price per unit as shown to the customer, or null for lump sums.
  static int? unitPrice(LineItem item, Rates rates) {
    if (item.unit.isLumpSum || item.quantity <= 0) return null;
    if (item.mode == PricingMode.unitRate) return item.unitPriceCents;
    return (line(item, rates) / item.quantity).round();
  }

  /// Totals for the lines in [tierId] (every line when null).
  static QuoteTotals totals({
    required Iterable<LineItem> items,
    required Rates rates,
    String? tierId,
    int discountCents = 0,
  }) {
    var subtotal = 0;
    var hours = 0.0;
    var materials = 0;
    var count = 0;
    for (final item in items) {
      if (!item.inTier(tierId)) continue;
      subtotal += line(item, rates);
      hours += item.laborHours;
      materials += item.materialCostCents;
      count++;
    }
    final minimum = subtotal > 0 && subtotal < rates.minimumJobCents
        ? rates.minimumJobCents - subtotal
        : 0;
    final discount = discountCents.clamp(0, subtotal + minimum);
    final taxable = subtotal + minimum - discount;
    final tax = (taxable * rates.taxRatePct / 100).round();
    final total = taxable + tax;
    final deposit = rates.depositPct <= 0
        ? 0
        : Money.roundDollars(
            (total * rates.depositPct / 100).round(),
          ).clamp(0, total);
    return QuoteTotals(
      subtotalCents: subtotal,
      minimumAdjustmentCents: minimum,
      discountCents: discount,
      taxCents: tax,
      totalCents: total,
      depositCents: deposit,
      laborHours: hours,
      materialCostCents: materials,
      lineCount: count,
    );
  }
}
