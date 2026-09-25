import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobwalk/services/api.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import 'helpers.dart';

void main() {
  testWidgets('setup takes three answers and lands on home', (tester) async {
    final app = await pumpApp(tester, settings: testSettings(setupDone: false));
    expect(find.text('Quote the job before you leave the driveway.'), findsOne);

    final start = find.widgetWithText(FilledButton, 'Start quoting');
    await scrollTo(tester, start);
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    await tester.drag(topList, const Offset(0, 3000));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Business name'),
      'Oak & Iron Fence Co.',
    );
    await tapText(tester, 'Fencing');
    // The labor rate is prefilled from the trade.
    await scrollTo(tester, find.text('60'));
    expect(find.text('60'), findsOne);

    await scrollTo(tester, start);
    await tester.tap(start);
    await tester.pumpAndSettle();

    expect(find.text('Your first quote is a few photos away.'), findsOne);
    expect(app.settings.profile.name, 'Oak & Iron Fence Co.');
    expect(app.settings.profile.trades, [Trade.fencing]);
    expect(app.settings.rates.laborRateCents, 6000);
    expect(app.settings.rates.minimumJobCents, 50000);
  });

  testWidgets('a sample job becomes a priced quote', (tester) async {
    final app = await pumpApp(tester);
    await tapText(tester, 'Living room repaint');

    expect(find.text('3 of 8'), findsOne);
    expect(
      find.text('Two coats on the walls. She asked about doing the trim too.'),
      findsOne,
    );

    await tapText(tester, 'Build quote');

    expect(find.text('Quote #1001'), findsOne);
    expect(find.text('Living room repaint'), findsOne);
    expect(find.text(r'$1,245'), findsWidgets);
    expect(find.text('Check before sending: 4'), findsOne);

    final quote = app.quotes.single;
    expect(quote.customer.name, 'Dana Ortiz');
    expect(quote.photoKeys, hasLength(3));
    expect(app.settings.nextNumber, 1002);
    final request = app.client.draftRequests.single;
    expect(request.photos, hasLength(3));
    expect(request.note, contains('trim'));
  });

  testWidgets('editing a line reprices the quote', (tester) async {
    final app = await pumpApp(tester);
    await tapText(tester, 'Living room repaint');
    await tapText(tester, 'Build quote');

    final walls = find.text('Paint walls, 2 coats');
    await scrollTo(tester, walls);
    await tester.tap(walls.first);
    await tester.pumpAndSettle();

    expect(find.text('Edit line'), findsOne);
    expect(
      find.text(r'4.5 hrs at $60 + $186 materials + 20%, rounded.'),
      findsOne,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Set your own price'),
      '550',
    );
    await tester.pumpAndSettle();
    expect(find.text('You set this price.'), findsOne);
    await tapText(tester, 'Save');

    expect(find.text(r'$1,300'), findsWidgets);
    final quote = app.quotes.single;
    expect(quote.totals('walls_trim').totalCents, 130000);
    expect(quote.changeFromDraft('walls_trim'), closeTo(4.42, 0.01));
  });

  testWidgets('send, customer approves, it shows as won', (tester) async {
    final app = await pumpApp(tester);
    await tapText(tester, 'Living room repaint');
    await tapText(tester, 'Build quote');

    await tapText(tester, 'Send to customer');
    expect(find.text('Send Quote #1001'), findsOne);
    expect(find.text(r'3 options, $725 to $1,410'), findsOne);
    expect(find.textContaining('4 assumptions are not checked'), findsOne);
    await tapText(tester, 'Copy link');

    var quote = app.quotes.single;
    expect(quote.status, QuoteStatus.sent);
    expect(clipboard, quote.share!.url);
    expect(find.text('Send again'), findsOne);

    // Play the customer: open the preview and approve the full room.
    await tester.tap(find.byTooltip('Preview as customer'));
    await tester.pumpAndSettle();
    expect(find.text('What Dana sees'), findsOne);
    await tapText(tester, 'Full room');
    final agree = find.byType(CheckboxListTile);
    await scrollTo(tester, agree);
    await tester.tap(agree);
    // Let the "link copied" message time out; it covers the button.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tapText(tester, r'Approve Full room: $1,410');

    quote = app.quotes.single;
    expect(quote.status, QuoteStatus.approved);
    expect(quote.chosenTierId, 'full_room');
    expect(quote.response.signature, 'Dana Ortiz');
    expect(find.text('Duplicate to make changes'), findsOne);
    expect(find.text('Approved: Full room'), findsOne);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Won in Sep'), findsOne);
    expect(find.text(r'$1,410'), findsWidgets);
    expect(find.text('Approved'), findsOne);
  });

  testWidgets('prices typed over a draft are learned when sent', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await tapText(tester, 'Living room repaint');
    await tapText(tester, 'Build quote');
    final walls = find.text('Paint walls, 2 coats');
    await scrollTo(tester, walls);
    await tester.tap(walls.first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Set your own price'),
      '600',
    );
    await tester.pumpAndSettle();
    await tapText(tester, 'Save');
    expect(app.settings.rates.priceList, isEmpty);

    await tapText(tester, 'Send to customer');
    await tapText(tester, 'Copy link');

    final learned = app.settings.rates.priceList.single;
    expect(learned.learned, isTrue);
    expect(learned.name, 'Paint walls, 2 coats');
    expect(learned.unitPriceCents, 150);
  });

  testWidgets('unusable photos ask for a retake', (tester) async {
    final app = await pumpApp(tester);
    app.client.nextDraft = AiDraft.fromJson({
      'photos_usable': false,
      'retake_advice': 'Too dark to see the walls. Turn on the lights.',
      'items': <Object?>[],
    });
    await tapText(tester, 'New quote');
    await tapText(tester, 'Take photo');
    await tapText(tester, 'Build quote');

    expect(find.text("These photos won't work"), findsOne);
    expect(
      find.text('Too dark to see the walls. Turn on the lights.'),
      findsOne,
    );
    await tapText(tester, 'Retake photos');
    expect(find.text('New quote'), findsOne);
    expect(app.quotes, isEmpty);
  });

  testWidgets('a failed draft can be retried', (tester) async {
    final app = await pumpApp(tester);
    app.client.failNext = const ApiError("Can't reach Jobwalk.");
    await tapText(tester, 'Driveway wash');
    await tapText(tester, 'Build quote');

    expect(find.text("Couldn't build the quote"), findsOne);
    expect(find.text("Can't reach Jobwalk."), findsOne);
    await tapText(tester, 'Try again');

    expect(find.text('Driveway and walkway wash'), findsOne);
    expect(app.quotes.single.tiers.map((t) => t.id), ['wash', 'wash_seal']);
  });

  testWidgets('new rates apply to new quotes only', (tester) async {
    final app = await pumpApp(tester);
    await tapText(tester, 'Living room repaint');
    await tapText(tester, 'Build quote');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tapText(tester, r'Labor $60/hr · materials +20%');
    await tester.enterText(
      find.widgetWithText(TextField, 'Labor per hour'),
      '80',
    );
    await tapText(tester, 'Save');
    expect(app.settings.rates.laborRateCents, 8000);
    expect(find.text(r'Labor $80/hr · materials +20%'), findsOne);

    // The quote already made keeps the rates it was priced with.
    expect(app.quotes.single.rates.laborRateCents, 6000);
    expect(app.quotes.single.totals().totalCents, 124500);
  });
}
