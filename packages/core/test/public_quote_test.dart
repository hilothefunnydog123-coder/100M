import 'dart:convert';

import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026, 9, 25, 15);

const profile = BusinessProfile(
  name: 'Brightline Painting',
  trades: [Trade.painting],
  phone: '512-555-0142',
  paymentLink: 'https://buy.stripe.com/test_123',
);

Quote quote() => QuoteBuilder.fromDraft(
  SampleJob.livingRoom.draft,
  id: 'q_1',
  number: 1042,
  rates: Rates.forTrade(Trade.painting),
  now: now,
  customer: const Customer(name: 'Dana Ortiz', address: '12 Elm St'),
);

void main() {
  test('one option per tier, with matching totals', () {
    final p = PublicQuote.fromQuote(quote(), profile, issuedAt: now);
    expect(p.options.map((o) => o.id), ['walls', 'walls_trim', 'full_room']);
    expect(p.defaultOption.id, 'walls_trim');
    expect(p.option('full_room')!.totalCents, 141000);
    expect(p.option('walls')!.lines, hasLength(4));
    expect(p.validUntil, now.add(const Duration(days: 30)));
    expect(p.validate(), isNull);
  });

  test('lines of one section stay together', () {
    final fence = QuoteBuilder.fromDraft(
      SampleJob.fence.draft,
      id: 'q_2',
      number: 1,
      rates: Rates.forTrade(Trade.fencing),
      now: now,
    );
    final p = PublicQuote.fromQuote(fence, profile, issuedAt: now);
    final sections = [for (final l in p.option('cedar_cap')!.lines) l.section];
    expect(sections, ['Removal', 'Posts', 'Fence', 'Fence', 'Gate']);
    expect(p.validate(), isNull);
    expect(groupBySection([1, 2, 3, 4, 5], (n) => n.isEven ? 'e' : 'o'), [
      1,
      3,
      5,
      2,
      4,
    ]);
  });

  test('a quote without tiers has a single option', () {
    final single = quote().copyWith(
      tiers: const [],
      items: [
        for (final i in quote().items)
          if (i.inTier('walls')) i.copyWith(tierIds: const {}),
      ],
    );
    final p = PublicQuote.fromQuote(single, profile, issuedAt: now);
    expect(p.options.single.id, 'quote');
    expect(p.options.single.totalCents, 72500);
    expect(p.validate(), isNull);
  });

  test('never includes costs, hours, or AI reasoning', () {
    final p = PublicQuote.fromQuote(quote(), profile, issuedAt: now);
    final json = jsonEncode(p.toJson());
    for (final secret in [
      'labor_hours',
      'material_cost',
      'other_cost',
      'basis',
      'assumptions',
      'owner_token',
      'price_list',
      'markup',
    ]) {
      expect(json, isNot(contains(secret)), reason: secret);
    }
  });

  test('JSON round trip validates', () {
    final p = PublicQuote.fromQuote(quote(), profile, issuedAt: now);
    final back = PublicQuote.fromJson(jsonDecode(jsonEncode(p.toJson())));
    expect(back.toJson(), p.toJson());
    expect(back.validate(), isNull);
    expect(back.business.paymentLink, profile.paymentLink);
  });

  group('validate', () {
    Map<String, Object?> json() =>
        PublicQuote.fromQuote(quote(), profile, issuedAt: now).toJson();

    String? check(void Function(Map<String, Object?>) tamper) {
      final j = jsonDecode(jsonEncode(json())) as Map<String, Object?>;
      tamper(j);
      return PublicQuote.fromJson(j).validate();
    }

    Map<String, Object?> firstOption(Map<String, Object?> j) =>
        (j['options'] as List).first as Map<String, Object?>;

    test('rejects totals that do not add up', () {
      expect(check((j) => firstOption(j)['total_cents'] = 1), isNotNull);
      expect(check((j) => firstOption(j)['subtotal_cents'] = 1), isNotNull);
      expect(
        check((j) => firstOption(j)['deposit_cents'] = 99999999),
        isNotNull,
      );
    });

    test('rejects missing pieces', () {
      expect(check((j) => j['business'] = {'name': ''}), isNotNull);
      expect(check((j) => j['options'] = <Object?>[]), isNotNull);
      expect(check((j) => firstOption(j)['lines'] = <Object?>[]), isNotNull);
      expect(check((j) => j['valid_until'] = j['issued_at']), isNotNull);
    });

    test('rejects duplicate option ids and negative amounts', () {
      expect(
        check((j) {
          final options = j['options'] as List;
          (options[1] as Map)['id'] = (options[0] as Map)['id'];
        }),
        isNotNull,
      );
      expect(
        check((j) {
          final line = (firstOption(j)['lines'] as List).first as Map;
          line['total_cents'] = -100;
        }),
        isNotNull,
      );
    });

    test('drops unsafe payment links', () {
      final p = PublicQuote.fromJson({
        ...json(),
        'business': {'name': 'X', 'payment_link': 'javascript:alert(1)'},
      });
      expect(p.business.paymentLink, isEmpty);
    });
  });
}
