import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026, 9, 25);

Quote quoteWith(List<LineItem> items) => Quote(
  id: 'q',
  number: 1,
  createdAt: now,
  updatedAt: now,
  rates: const Rates(),
  items: items,
);

LineItem aiLine(
  String description, {
  double quantity = 100,
  Unit unit = Unit.sqFt,
}) => LineItem(
  id: description,
  description: description,
  quantity: quantity,
  unit: unit,
  laborHours: 2,
  fromAi: true,
);

void main() {
  test('a re-priced AI line becomes a learned price', () {
    final rates = PriceMemory.learn(
      const Rates(),
      quoteWith([aiLine('Paint walls, 2 coats').withTotal(25000)]),
      now: now,
    );
    final entry = rates.priceList.single;
    expect(entry.learned, isTrue);
    expect(entry.name, 'Paint walls, 2 coats');
    expect(entry.unit, Unit.sqFt);
    expect(entry.unitPriceCents, 250);
    expect(entry.updatedAt, now);
    expect(entry.id, startsWith('learned_'));
  });

  test('typed unit prices are learned, price-list prices are not', () {
    final rates = PriceMemory.learn(
      const Rates(),
      quoteWith([
        aiLine('Typed').withUnitPrice(300),
        aiLine('From list').withUnitPrice(300, priceListId: 'p1'),
        aiLine('Untouched'),
      ]),
      now: now,
    );
    expect(rates.priceList.map((e) => e.name), ['Typed']);
  });

  test('skips lump sums, zero quantities, and lines the pro added', () {
    final added = const LineItem(
      id: 'x',
      description: 'Added by hand',
      quantity: 10,
      unit: Unit.sqFt,
    ).withTotal(1000);
    final rates = PriceMemory.learn(
      const Rates(),
      quoteWith([
        aiLine('Lump', unit: Unit.lot).withTotal(1000),
        aiLine('Zero', quantity: 0).withTotal(1000),
        added,
      ]),
      now: now,
    );
    expect(rates.priceList, isEmpty);
  });

  test('updates the same learned entry and respects manual ones', () {
    final manual = const PriceEntry(
      id: 'p1',
      name: 'Paint ceiling',
      unit: Unit.sqFt,
      unitPriceCents: 150,
    );
    var rates = Rates(priceList: [manual]);
    rates = PriceMemory.learn(
      rates,
      quoteWith([
        aiLine('Paint walls').withTotal(20000),
        aiLine('Paint  CEILING!').withTotal(99900),
      ]),
      now: now,
    );
    expect(rates.priceList, hasLength(2));
    expect(rates.priceEntry('p1')!.unitPriceCents, 150);

    final later = now.add(const Duration(days: 1));
    rates = PriceMemory.learn(
      rates,
      quoteWith([aiLine('paint walls').withTotal(30000)]),
      now: later,
    );
    final learned = rates.priceList.where((e) => e.learned).single;
    expect(learned.unitPriceCents, 300);
    expect(learned.updatedAt, later);
  });

  test('keeps only the most recent learned entries', () {
    var rates = const Rates();
    for (var i = 0; i < PriceMemory.maxLearned + 5; i++) {
      rates = PriceMemory.learn(
        rates,
        quoteWith([aiLine('Item $i').withTotal(10000)]),
        now: now.add(Duration(minutes: i)),
      );
    }
    expect(rates.priceList, hasLength(PriceMemory.maxLearned));
    expect(rates.priceList.any((e) => e.name == 'Item 0'), isFalse);
    expect(
      rates.priceList.any(
        (e) => e.name == 'Item ${PriceMemory.maxLearned + 4}',
      ),
      isTrue,
    );
  });

  test('the builder prices matching lines from the list', () {
    const rates = Rates(
      priceList: [
        PriceEntry(
          id: 'p1',
          name: 'Walls',
          unit: Unit.sqFt,
          unitPriceCents: 210,
        ),
      ],
    );
    final draft = AiDraft.fromJson({
      'items': [
        {
          'description': 'Paint walls',
          'quantity': 1000,
          'unit': 'sq_ft',
          'price_list_id': 'p1',
          'labor_hours': 10,
        },
        {
          'description': 'Wrong unit',
          'quantity': 50,
          'unit': 'ln_ft',
          'price_list_id': 'p1',
          'labor_hours': 1,
        },
        {
          'description': 'Unknown entry',
          'quantity': 1,
          'unit': 'lot',
          'price_list_id': 'nope',
          'labor_hours': 1,
        },
      ],
    });
    final q = QuoteBuilder.fromDraft(
      draft,
      id: 'q',
      number: 1,
      rates: rates,
      now: now,
    );
    expect(q.items[0].mode, PricingMode.unitRate);
    expect(Pricing.line(q.items[0], rates), 210000);
    expect(q.items[1].mode, PricingMode.cost);
    expect(q.items[1].priceListId, isNull);
    expect(q.items[2].priceListId, isNull);
  });
}
