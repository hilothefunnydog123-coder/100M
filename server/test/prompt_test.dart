import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('describeJob', () {
    test('includes the business, rates, and note', () {
      final text = describeJob(draftRequest());
      expect(text, contains('Business: Oak & Iron Fence Co.'));
      expect(text, contains('Trades: Fencing'));
      expect(text, contains('ZIP 78704'));
      expect(text, contains(r'Labor rate: $60.00 per person-hour'));
      expect(text, contains('Material markup: 20%'));
      expect(text, contains('no price list yet'));
      expect(text, contains('"Customer wants cedar"'));
      expect(text, endsWith('from the 2 photos above.'));
    });

    test('lists the price list with ids and learned markers', () {
      final text = describeJob(
        draftRequest(
          photos: 1,
          note: '',
          priceList: const [
            PriceEntry(
              id: 'p1',
              name: 'Cedar privacy fence, installed',
              unit: Unit.lnFt,
              unitPriceCents: 4250,
            ),
            PriceEntry(
              id: 'learned_1',
              name: 'Tear out old fence',
              unit: Unit.lnFt,
              unitPriceCents: 575,
              learned: true,
            ),
          ],
        ),
      );
      expect(
        text,
        contains(r'- p1: Cedar privacy fence, installed: $42.50 per ln ft'),
      );
      expect(text, contains(r'$5.75 per ln ft (from their past quotes)'));
      expect(text, contains("didn't add a note"));
      expect(text, endsWith('from the 1 photo above.'));
    });

    test('fractional markup is printed as given', () {
      final r = draftRequest();
      final text = describeJob(
        DraftRequest(
          profile: r.profile,
          rates: r.rates.copyWith(materialMarkupPct: 12.5),
          photos: r.photos,
        ),
      );
      expect(text, contains('Material markup: 12.5%'));
    });
  });

  group('schema', () {
    void checkObjects(Object? node, String path) {
      if (node is Map) {
        if (node['type'] == 'object') {
          final props = (node['properties'] as Map).keys.toList();
          expect(node['required'], props, reason: path);
          expect(node['additionalProperties'], isFalse, reason: path);
        }
        for (final e in node.entries) {
          checkObjects(e.value, '$path.${e.key}');
        }
      } else if (node is List) {
        for (final (i, e) in node.indexed) {
          checkObjects(e, '$path[$i]');
        }
      }
    }

    test('every object requires all properties and allows no others', () {
      checkObjects(draftSchema, 'draft');
    });

    test('units match the shared model', () {
      final item =
          ((draftSchema['properties'] as Map)['items'] as Map)['items'] as Map;
      final unit = (item['properties'] as Map)['unit'] as Map;
      expect(unit['enum'], [for (final u in Unit.values) u.id]);
    });

    test('the model looks before it prices and names the job last', () {
      final keys = (draftSchema['properties'] as Map).keys.toList();
      expect(keys.first, 'photos_usable');
      expect(keys.indexOf('measurements'), lessThan(keys.indexOf('items')));
      expect(keys.indexOf('items'), lessThan(keys.indexOf('title')));
      final item =
          ((draftSchema['properties'] as Map)['items'] as Map)['items'] as Map;
      final itemKeys = (item['properties'] as Map).keys.toList();
      expect(
        itemKeys.indexOf('basis'),
        lessThan(itemKeys.indexOf('labor_hours')),
      );
    });

    test('a draft in the schema shape parses back', () {
      final json = draftJson();
      final keys = (draftSchema['properties'] as Map).keys.toSet();
      expect(json.keys.toSet(), keys);
    });
  });

  test('the system prompt never asks the model for prices or totals', () {
    expect(systemPrompt, contains('You never write a price or a total'));
    expect(systemPrompt, isNot(contains('{')));
  });
}
