import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobwalk/state/providers.dart';
import 'package:jobwalk/state/session.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import 'fake_backend.dart';
import 'helpers.dart';

void main() {
  testWidgets('sign in, set up, draft, send, and see the approval', (
    tester,
  ) async {
    final backend = FakeBackend();
    final container = await pumpConnectedApp(tester, backend);

    expect(find.text('Sign in to Jobwalk'), findsOne);
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'dana@example.com',
    );
    await tester.pump();
    await tapText(tester, 'Email me a code');
    expect(find.text('Check your email'), findsOne);
    expect(backend.codeSentTo, 'dana@example.com');

    await tester.enterText(
      find.widgetWithText(TextField, 'Code'),
      FakeBackend.code,
    );
    await tester.pumpAndSettle();

    // A new business: set it up once, and it's saved to the account.
    expect(find.text('Quote the job before you leave the driveway.'), findsOne);
    await tester.enterText(
      find.widgetWithText(TextField, 'Business name'),
      'Brightline Painting',
    );
    await tapText(tester, 'Painting');
    await tapText(tester, 'Start quoting');
    expect(find.text('Your first quote is a few photos away.'), findsOne);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(backend.profile['name'], 'Brightline Painting');

    await tapText(tester, 'Living room repaint');
    await tapText(tester, 'Build quote');
    expect(find.text('Quote #1001'), findsOne);
    expect(backend.calls, contains('POST /v1/drafts'));

    await tapText(tester, 'Send to customer');
    await tapText(tester, 'Copy link');
    final quote = container.read(quotesProvider).single;
    expect(quote.status, QuoteStatus.sent);
    expect(clipboard, quote.share!.url);
    expect(clipboard, startsWith('https://jobwalk.test/q/'));
    expect(backend.quote(quote.id), isNotNull);

    // The customer approves on their phone; the next sync brings it in.
    backend.customerApproves(quote.id, option: 'full_room', name: 'Dana O.');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.fling(topList, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    final won = container.read(quotesProvider).single;
    expect(won.status, QuoteStatus.approved);
    expect(find.text('Won in Sep'), findsOne);
    expect(find.text(r'$1,410'), findsWidgets);
  });

  testWidgets('a used-up trial offers plans', (tester) async {
    final backend = FakeBackend()
      ..profile = {
        'name': 'Brightline Painting',
        'trades': ['painting'],
      }
      ..draftsLeft = 0;
    await pumpConnectedApp(
      tester,
      backend,
      signedIn: true,
      settings: testSettings(),
    );
    await tapText(tester, 'Living room repaint');
    await tapText(tester, 'Build quote');
    expect(find.text("Couldn't build the quote"), findsOne);
    expect(find.textContaining('25 free AI drafts'), findsOne);
    await tapText(tester, 'See plans');
    expect(find.text('Choose a plan'), findsOne);
    expect(find.text('Choose Pro'), findsOne);
    expect(find.text('Choose Crew'), findsOne);
  });

  testWidgets('settings show the plan, team, and sign out', (tester) async {
    final backend = FakeBackend()
      ..profile = {
        'name': 'Brightline Painting',
        'trades': ['painting'],
      }
      ..draftsLeft = 22;
    final container = await pumpConnectedApp(
      tester,
      backend,
      signedIn: true,
      settings: testSettings(),
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('dana@example.com'), findsWidgets);
    expect(find.text('Free trial'), findsOne);
    expect(find.textContaining('22 of 25 free AI drafts left'), findsOne);
    expect(find.text('Take deposits by card'), findsOne);

    await tapText(tester, 'Sign out');
    expect(find.text('Sign out?'), findsOne);
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Jobwalk'), findsOne);
    expect(container.read(sessionProvider).signedIn, isFalse);
    expect(backend.signedOut, isTrue);
  });

  testWidgets('members see the business settings but cannot change them', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..role = 'member'
      ..profile = {
        'name': 'Brightline Painting',
        'trades': ['painting'],
      };
    await pumpConnectedApp(
      tester,
      backend,
      signedIn: true,
      settings: testSettings(),
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Team member · Brightline Painting'), findsOne);
    await scrollTo(
      tester,
      find.text('The account owner sets the business details and prices.'),
    );
    expect(find.text('Choose a plan'), findsNothing);
  });
}
