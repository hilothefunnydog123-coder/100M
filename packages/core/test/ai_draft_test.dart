import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:test/test.dart';

Map<String, Object?> item(
  String description, {
  List<String> tiers = const [],
  Object? unit = 'lot',
  Object? quantity = 1,
  Object? hours = 1,
}) => {
  'section': 'Work',
  'description': description,
  'detail': '',
  'quantity': quantity,
  'unit': unit,
  'price_list_id': '',
  'labor_hours': hours,
  'material_cost': 10.5,
  'other_cost': 0,
  'tiers': tiers,
  'basis': 'because',
};

Map<String, Object?> tier(String id, {bool recommended = false}) => {
  'id': id,
  'name': id.toUpperCase(),
  'summary': '',
  'recommended': recommended,
};

AiDraft parse({
  List<Map<String, Object?>> tiers = const [],
  required List<Map<String, Object?>> items,
}) => AiDraft.fromJson({
  'photos_usable': true,
  'title': 'Job',
  'tiers': tiers,
  'items': items,
});

void main() {
  test('parses lines and converts dollars to cents', () {
    final d = parse(items: [item('Paint', unit: 'sq_ft', quantity: 400)]);
    final line = d.items.single;
    expect(line.id, 'l1');
    expect(line.unit, Unit.sqFt);
    expect(line.quantity, 400);
    expect(line.materialCostCents, 1050);
    expect(line.fromAi, isTrue);
    expect(d.isUsable, isTrue);
  });

  test('clamps and cleans bad values', () {
    final d = parse(
      items: [
        item('', hours: 3),
        item('Huge', unit: 'sq_ft', quantity: 1e12, hours: -4),
        item('Odd unit', unit: 'furlongs', quantity: 'many'),
        item('Lump', unit: 'lot', quantity: 7),
      ],
    );
    expect(d.items.map((i) => i.description), ['Huge', 'Odd unit', 'Lump']);
    expect(d.items[0].quantity, LineItem.maxQuantity);
    expect(d.items[0].laborHours, 0);
    expect(d.items[1].unit, Unit.each);
    expect(d.items[1].quantity, 1);
    // A lump sum is always one lot.
    expect(d.items[2].quantity, 1);
  });

  test('caps the number of lines', () {
    final d = parse(items: [for (var i = 0; i < 60; i++) item('Line $i')]);
    expect(d.items, hasLength(AiDraft.maxItems));
  });

  test('photos marked unusable are not a usable draft', () {
    final d = AiDraft.fromJson({
      'photos_usable': false,
      'retake_advice': 'Too dark. Turn on the lights.',
      'items': <Object?>[],
    });
    expect(d.isUsable, isFalse);
    expect(d.retakeAdvice, contains('Too dark'));
  });

  group('options', () {
    test('keeps valid tiers and maps lines to them', () {
      final d = parse(
        tiers: [tier('good'), tier('best', recommended: true)],
        items: [
          item('Shared'),
          item('Standard paint', tiers: ['good']),
          item('Premium paint', tiers: ['best']),
          item('Listed under both', tiers: ['good', 'best']),
        ],
      );
      expect(d.tiers.map((t) => t.id), ['good', 'best']);
      expect(d.tiers.map((t) => t.recommended), [false, true]);
      expect(d.items[0].tierIds, isEmpty);
      expect(d.items[1].tierIds, {'good'});
      // A line in every option is stored as "all options".
      expect(d.items[3].tierIds, isEmpty);
    });

    test('only the first recommendation counts', () {
      final d = parse(
        tiers: [tier('a', recommended: true), tier('b', recommended: true)],
        items: [
          item('A', tiers: ['a']),
          item('B', tiers: ['b']),
        ],
      );
      expect(d.tiers.where((t) => t.recommended).single.id, 'a');
    });

    test('drops options with no lines', () {
      final d = parse(
        tiers: [tier('a'), tier('b'), tier('empty')],
        items: [
          item('A', tiers: ['a']),
          item('B', tiers: ['b']),
        ],
      );
      expect(d.tiers.map((t) => t.id), ['a', 'b']);
    });

    test('a single option collapses without double counting', () {
      final d = parse(
        tiers: [tier('good'), tier('best', recommended: true)],
        items: [
          item('Shared'),
          item('Premium paint', tiers: ['best']),
          item('Standard paint', tiers: ['nonexistent']),
        ],
      );
      // "good" has only the shared line and the unknown-tier line (treated
      // as shared), so both tiers have lines; nothing collapses here.
      expect(d.tiers, hasLength(2));

      final single = parse(
        tiers: [tier('only')],
        items: [
          item('Shared'),
          item('Only', tiers: ['only']),
        ],
      );
      expect(single.tiers, isEmpty);
      expect(single.items.map((i) => i.description), ['Shared', 'Only']);
      expect(single.items.every((i) => i.tierIds.isEmpty), isTrue);
    });

    test('collapses to the recommended option when the rest are empty', () {
      final d = parse(
        tiers: [tier('good'), tier('best', recommended: true), tier('x')],
        items: [
          item('Premium', tiers: ['best']),
        ],
      );
      expect(d.tiers, isEmpty);
      expect(d.items.single.description, 'Premium');
    });

    test('duplicate and extra tiers are dropped', () {
      final d = parse(
        tiers: [tier('a'), tier('a'), tier('b'), tier('c'), tier('d')],
        items: [
          item('A', tiers: ['a']),
          item('B', tiers: ['b']),
          item('C', tiers: ['c']),
          item('D', tiers: ['d']),
        ],
      );
      expect(d.tiers.map((t) => t.id), ['a', 'b', 'c']);
    });
  });

  test('JSON round trip preserves every priced field', () {
    final original = SampleJob.fence.draft;
    final again = AiDraft.fromJson(original.toJson());
    expect(again.toJson(), original.toJson());
  });
}
