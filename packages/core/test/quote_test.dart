import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026, 9, 25, 15);

Quote sampleQuote({SampleJob job = SampleJob.livingRoom, Rates? rates}) =>
    QuoteBuilder.fromDraft(
      job.draft,
      id: 'q_test',
      number: 1042,
      rates: rates ?? Rates.forTrade(job.trade),
      now: now,
      customer: const Customer(name: 'Dana Ortiz'),
      model: 'demo',
      demo: true,
    );

void main() {
  group('sample quotes price out as written', () {
    test('living room at painting rates', () {
      final q = sampleQuote();
      expect(q.defaultTierId, 'walls_trim');
      expect(q.totals('walls').totalCents, 72500);
      expect(q.totals('walls_trim').totalCents, 124500);
      expect(q.totals('full_room').totalCents, 141000);
      expect(q.totals().totalCents, 124500);
      expect(q.totals('walls_trim').depositCents, 31100);
      expect(q.ai!.draftTotals, {
        'walls': 72500,
        'walls_trim': 124500,
        'full_room': 141000,
      });
    });

    test('fence at fencing rates', () {
      final q = sampleQuote(job: SampleJob.fence);
      expect(q.totals('pine').totalCents, 406500);
      expect(q.totals('cedar').totalCents, 465500);
      expect(q.totals('cedar_cap').totalCents, 525500);
    });

    test('driveway at pressure washing rates', () {
      final q = sampleQuote(job: SampleJob.driveway);
      expect(q.totals('wash').totalCents, 20900);
      expect(q.totals('wash_seal').totalCents, 45900);
    });

    test('prices follow the contractor rates', () {
      final cheap = sampleQuote(
        rates: const Rates(laborRateCents: 4000, materialMarkupPct: 0),
      );
      final pricey = sampleQuote(
        rates: const Rates(laborRateCents: 9000, materialMarkupPct: 35),
      );
      expect(cheap.totals().totalCents, lessThan(pricey.totals().totalCents));
    });
  });

  test('changeFromDraft reports the edit in percent', () {
    final q = sampleQuote();
    expect(q.changeFromDraft(), 0);
    final walls = q.items.firstWhere(
      (i) => i.description == 'Paint walls, 2 coats' && i.inTier('walls_trim'),
    );
    final edited = q.replaceItem(walls.withTotal(49500 + 12450));
    expect(edited.changeFromDraft(), closeTo(10, 0.01));
  });

  test('editing helpers', () {
    final q = sampleQuote();
    final first = q.items.first;
    expect(q.item(first.id), same(first));
    final removed = q.removeItem(first.id);
    expect(removed.items, hasLength(q.items.length - 1));
    expect(removed.item(first.id), isNull);
  });

  test('labels and dates', () {
    final q = sampleQuote();
    expect(q.label, 'Quote #1042');
    expect(q.displayName, 'Dana Ortiz');
    expect(
      q.copyWith(customer: const Customer()).displayName,
      'Living room repaint',
    );
    expect(q.validUntil, now.add(const Duration(days: 30)));
    expect(q.openAssumptions, q.assumptions.length);
    expect(q.customer.firstName, 'Dana');
  });

  group('applyResponse', () {
    final sent = sampleQuote().copyWith(status: QuoteStatus.sent);

    test('a view moves sent to viewed', () {
      final q = sent.applyResponse(const CustomerResponse(views: 2));
      expect(q.status, QuoteStatus.viewed);
      expect(q.response.views, 2);
    });

    test('an approval records the option and time', () {
      final at = now.add(const Duration(hours: 3));
      final q = sent.applyResponse(
        CustomerResponse(
          views: 1,
          approvedAt: at,
          approvedTierId: 'full_room',
          signature: 'Dana Ortiz',
        ),
      );
      expect(q.status, QuoteStatus.approved);
      expect(q.chosenTierId, 'full_room');
      expect(q.closedAt, at);
      expect(q.headlineTotalCents, 141000);
    });

    test('a decline closes it, but not over a manual approval', () {
      final declined = sent.applyResponse(
        CustomerResponse(declinedAt: now, declineReason: 'Too much'),
      );
      expect(declined.status, QuoteStatus.declined);

      final manual = sent.copyWith(status: QuoteStatus.approved);
      expect(
        manual.applyResponse(CustomerResponse(declinedAt: now)).status,
        QuoteStatus.approved,
      );
      expect(
        manual.applyResponse(const CustomerResponse(views: 3)).status,
        QuoteStatus.approved,
      );
    });
  });

  test('JSON round trip', () {
    final q = sampleQuote().copyWith(
      status: QuoteStatus.viewed,
      discountCents: 2500,
      photoKeys: ['p1', 'p2'],
      share: ShareInfo(
        publicId: 'pub_1',
        url: 'https://jobwalk.app/q/pub_1',
        ownerToken: 'secret',
        sentAt: now,
      ),
      response: CustomerResponse(views: 1, firstViewedAt: now),
    );
    final back = Quote.fromJson(q.toJson())!;
    expect(back.toJson(), q.toJson());
    expect(Quote.fromJson({'id': 'x'}), isNull);
  });
}
