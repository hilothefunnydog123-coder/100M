import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:test/test.dart';

const rates = Rates(
  laborRateCents: 6000,
  materialMarkupPct: 20,
  minimumJobCents: 50000,
  depositPct: 25,
);

LineItem line(
  String id, {
  double hours = 0,
  int materials = 0,
  int other = 0,
  double quantity = 1,
  Unit unit = Unit.lot,
  Set<String> tiers = const {},
}) => LineItem(
  id: id,
  description: id,
  laborHours: hours,
  materialCostCents: materials,
  otherCostCents: other,
  quantity: quantity,
  unit: unit,
  tierIds: tiers,
);

void main() {
  group('Pricing.line', () {
    test('labor at the rate, materials marked up, other at cost', () {
      final item = line('a', hours: 4.5, materials: 18600, other: 1000);
      expect(Pricing.costBased(item, rates), 27000 + 22320 + 1000);
      // $503.20 rounds to $505.
      expect(Pricing.line(item, rates), 50500);
    });

    test('exact cents when rounding is off', () {
      final item = line('a', hours: 4.5, materials: 18600);
      expect(Pricing.line(item, rates.copyWith(roundPrices: false)), 49320);
    });

    test('unit rates multiply by quantity', () {
      final item = line(
        'a',
        quantity: 1240,
        unit: Unit.sqFt,
      ).withUnitPrice(210);
      expect(item.mode, PricingMode.unitRate);
      // $2,604 rounds to $2,600.
      expect(Pricing.line(item, rates), 260000);
      expect(Pricing.unitPrice(item, rates), 210);
    });

    test('a typed total wins and is never rounded', () {
      final item = line('a', hours: 10).withTotal(123456);
      expect(item.mode, PricingMode.fixed);
      expect(Pricing.line(item, rates), 123456);
      expect(item.withoutOverride().mode, PricingMode.cost);
      final listed = line(
        'b',
        quantity: 10,
        unit: Unit.sqFt,
      ).withUnitPrice(200, priceListId: 'p1').withTotal(5000).withoutOverride();
      expect(listed.mode, PricingMode.unitRate);
      expect(listed.priceListId, 'p1');
    });

    test('unit price for lump sums is null', () {
      expect(Pricing.unitPrice(line('a', hours: 1), rates), isNull);
      final perFoot = line('b', hours: 10, quantity: 100, unit: Unit.lnFt);
      expect(Pricing.unitPrice(perFoot, rates), 600);
    });
  });

  group('Pricing.totals', () {
    test('sums the lines in an option', () {
      final items = [
        line('shared', hours: 2),
        line('good', hours: 1, tiers: {'good'}),
        line('best', hours: 10, tiers: {'best'}),
      ];
      final good = Pricing.totals(items: items, rates: rates, tierId: 'good');
      expect(good.lineCount, 2);
      expect(good.subtotalCents, 12000 + 6000);
      final best = Pricing.totals(items: items, rates: rates, tierId: 'best');
      expect(best.subtotalCents, 12000 + 60000);
      final all = Pricing.totals(items: items, rates: rates);
      expect(all.lineCount, 3);
    });

    test('raises small jobs to the minimum', () {
      final t = Pricing.totals(items: [line('a', hours: 5)], rates: rates);
      expect(t.subtotalCents, 30000);
      expect(t.minimumAdjustmentCents, 20000);
      expect(t.totalCents, 50000);
    });

    test('no minimum on an empty quote', () {
      final t = Pricing.totals(items: const [], rates: rates);
      expect(t.totalCents, 0);
      expect(t.minimumAdjustmentCents, 0);
    });

    test('discount, then tax, then deposit rounded to dollars', () {
      final t = Pricing.totals(
        items: [line('a', hours: 20)],
        rates: rates.copyWith(taxRatePct: 8.25),
        discountCents: 10000,
      );
      expect(t.subtotalCents, 120000);
      expect(t.discountCents, 10000);
      expect(t.taxCents, 9075);
      expect(t.totalCents, 119075);
      expect(t.depositCents, 29800); // 25% of $1,190.75 = $297.69 -> $298
    });

    test('a discount cannot make the total negative', () {
      final t = Pricing.totals(
        items: [line('a', hours: 10)],
        rates: rates,
        discountCents: 999999,
      );
      expect(t.totalCents, 0);
      expect(t.depositCents, 0);
    });

    test('tracks hours and material cost for the contractor', () {
      final t = Pricing.totals(
        items: [
          line('a', hours: 2.5, materials: 1000),
          line('b', hours: 1, materials: 500),
        ],
        rates: rates,
      );
      expect(t.laborHours, 3.5);
      expect(t.materialCostCents, 1500);
    });
  });

  group('LineItem edits', () {
    test('changing the quantity keeps the price per unit', () {
      final item = line(
        'a',
        hours: 10,
        materials: 20000,
        other: 1000,
        quantity: 100,
        unit: Unit.lnFt,
      );
      final longer = item.withQuantity(150);
      expect(longer.quantity, 150);
      expect(longer.laborHours, 15);
      expect(longer.materialCostCents, 30000);
      expect(longer.otherCostCents, 1500);

      final typed = item.withTotal(100000).withQuantity(50);
      expect(typed.priceOverrideCents, 50000);
    });

    test('lump sums and zero quantities just take the new number', () {
      final lump = line('a', hours: 3).withQuantity(5);
      expect(lump.laborHours, 3);
      final zero = line(
        'b',
        hours: 3,
        quantity: 0,
        unit: Unit.sqFt,
      ).withQuantity(100);
      expect(zero.laborHours, 3);
      expect(zero.quantity, 100);
    });

    test('withCosts returns to cost pricing', () {
      final item = line(
        'a',
        hours: 1,
      ).withUnitPrice(500, priceListId: 'p1').withTotal(9900);
      final back = item.withCosts(laborHours: 2);
      expect(back.mode, PricingMode.cost);
      expect(back.priceListId, isNull);
      expect(back.laborHours, 2);
    });

    test('JSON round trip', () {
      const item = LineItem(
        id: 'x',
        description: 'Paint walls',
        detail: 'Eggshell',
        section: 'Walls',
        quantity: 400,
        unit: Unit.sqFt,
        laborHours: 4.5,
        materialCostCents: 11400,
        otherCostCents: 50,
        unitPriceCents: 210,
        priceListId: 'p1',
        tierIds: {'good'},
        basis: 'Measured',
        fromAi: true,
      );
      final back = LineItem.fromJson(item.toJson())!;
      expect(back.toJson(), item.toJson());
    });

    test('fromJson rejects lines without an id or description', () {
      expect(LineItem.fromJson({'id': 'x'}), isNull);
      expect(LineItem.fromJson({'description': 'x'}), isNull);
      expect(LineItem.fromJson('nope'), isNull);
    });
  });
}
