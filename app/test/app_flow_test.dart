import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotcheck/services/analysis_service.dart';
import 'package:spotcheck/state/check_flow.dart';
import 'package:spotcheck/state/providers.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

import 'helpers.dart';

void main() {
  testWidgets('onboarding requires both consents before continuing', (
    tester,
  ) async {
    final app = await pumpApp(tester, settings: testSettings(onboarded: false));
    expect(find.text("Know what you're looking at."), findsOneWidget);

    await tapText(tester, 'Get started');
    await tapText(tester, 'Next');
    await tapText(tester, 'Next');
    expect(find.text('SpotCheck is not a doctor'), findsOneWidget);

    FilledButton button() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'I understand'),
    );
    expect(button().onPressed, isNull);
    await tapText(
      tester,
      'I understand SpotCheck gives information, not a diagnosis, and '
      "doesn't replace a medical professional.",
    );
    expect(button().onPressed, isNull, reason: 'one consent is not enough');
    await tapText(
      tester,
      "I'm 18 or older, or a parent or guardian checking for my child.",
    );
    expect(button().onPressed, isNotNull);

    await tapText(tester, 'I understand');
    expect(find.text('A little about you'), findsOneWidget);
    expect(find.text('Your age'), findsOneWidget);
    await tapText(tester, '40 to 64 years');
    await tapText(tester, 'Continue');

    expect(find.text('What should we look at?'), findsOneWidget);
    final settings = app.container.read(settingsProvider);
    expect(settings.onboarded, isTrue);
    expect(settings.profileAnswers.single(Q.ageBand), '40_64');
  });

  testWidgets('home shows an empty state and free checks', (tester) async {
    await pumpApp(tester, freeChecks: 3);
    expect(find.text('No checks yet'), findsOneWidget);
    expect(find.text('3 free checks left'), findsOneWidget);
    expect(find.text('Emergency? Call 911'), findsOneWidget);
  });

  testWidgets('a full check saves a result to history', (tester) async {
    final app = await pumpApp(tester);

    await tapText(tester, 'Start a check');
    expect(find.text('Where is it?'), findsOneWidget);
    await tapText(tester, 'Back');
    await tapText(tester, 'Me');
    expect(find.text('Take a clear photo'), findsOneWidget);

    FilledButton continueButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(continueButton().onPressed, isNull, reason: 'photo required');
    app.container.read(checkFlowProvider.notifier).setPhoto(testPhoto());
    await tester.pumpAndSettle();
    expect(find.text('Looks good'), findsOneWidget);
    await tapText(tester, 'Continue');

    // The profile answered age, so it starts with the optional questions.
    expect(find.text('QUESTION 1 OF 8'), findsOneWidget);
    expect(find.text('How old is the person?'), findsNothing);
    await tapText(tester, 'Skip');
    await tapText(tester, 'Skip');
    await tapText(tester, 'None of these');
    await tapText(tester, 'Next');
    await tapText(tester, 'A mole or dark spot');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Is any of this true about the spot?'), findsOneWidget);
    await tapText(tester, "One half doesn't match the other");
    await tapText(tester, 'Next');
    await tapText(tester, 'Over a year');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tapText(tester, 'Staying the same');
    await tapText(tester, 'Next');
    await tapText(tester, 'None of these');
    await tapText(tester, 'Next');
    await tapText(tester, 'None of these');
    await tapText(tester, 'Next');

    expect(find.text('Anything else we should know?'), findsOneWidget);
    expect(find.text('This uses 1 of your 3 free checks'), findsOneWidget);
    await tapText(tester, 'Analyze');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(find.text('Your result'), findsOneWidget);
    expect(find.text('Book a doctor visit'), findsWidgets);
    expect(await scrollToText(tester, 'Why this advice'), isTrue);
    expect(await scrollToText(tester, 'Melanoma'), isTrue);

    final request = app.analysis.requests.single;
    expect(request.site, BodySite.back);
    expect(request.answers.single(Q.ageBand), '18_39');
    expect(request.answers[Q.moleFeatures], {'asymmetric'});
    expect(request.photos.single.mediaType, 'image/jpeg');

    final history = app.container.read(historyProvider);
    expect(history, hasLength(1));
    expect(history.single.site, BodySite.back);
    expect(app.container.read(settingsProvider).checksUsed, 1);

    await tapText(tester, 'Done');
    expect(find.text('What should we look at?'), findsOneWidget);
    expect(find.text('No checks yet'), findsNothing);
    expect(find.text('2 free checks left'), findsOneWidget);
  });

  testWidgets('emergency answers are intercepted before analysis', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await tapText(tester, 'Start a check');
    await tapText(tester, 'Eye');
    await tapText(tester, 'Someone else');
    app.container.read(checkFlowProvider.notifier).setPhoto(testPhoto());
    await tester.pumpAndSettle();
    await tapText(tester, 'Continue');

    await tapText(tester, '18 to 39 years');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tapText(tester, 'Skip');
    await tapText(tester, 'Skip');
    await tapText(tester, 'None of these');
    await tapText(tester, 'Next');
    await tapText(tester, 'Chemical splash in the eye');
    await tapText(tester, 'Next');
    await tapText(tester, 'Less than a day');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tapText(tester, 'None of these');
    await tapText(tester, 'Next');
    await tapText(tester, 'Analyze');

    expect(find.text('This could be an emergency'), findsOneWidget);
    expect(find.textContaining('15 minutes'), findsOneWidget);
    expect(find.text('Call 911'), findsOneWidget);
    expect(app.analysis.requests, isEmpty, reason: 'not analyzed yet');

    await tapText(tester, 'Continue to photo analysis');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('Get emergency care now'), findsOneWidget);
    // Escalated: the model's reassuring headline is replaced.
    expect(find.text('Your answers point to an emergency.'), findsOneWidget);
    expect(find.textContaining('clears on its own'), findsNothing);
    expect(
      await scrollToText(tester, 'Raised by SpotCheck safety rules'),
      isTrue,
    );
  });

  testWidgets('the paywall appears when free checks are used up', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      settings: testSettings(checksUsed: 3),
      freeChecks: 3,
    );
    expect(find.text('0 free checks left'), findsOneWidget);
    await tapText(tester, 'Start a check');
    expect(find.text('Keep checking with SpotCheck Pro'), findsOneWidget);
    expect(
      await scrollToText(tester, 'Development build: purchases are simulated'),
      isTrue,
    );

    await tapText(tester, 'Start 7-day free trial');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(app.container.read(settingsProvider).pro, isTrue);
    expect(find.text('Where is it?'), findsOneWidget);
  });

  testWidgets('analysis errors can be retried', (tester) async {
    final app = await pumpApp(
      tester,
      analysis: FakeAnalysisService(
        error: const AnalysisError('SpotCheck is very busy right now.'),
      ),
    );
    await tapText(tester, 'Start a check');
    await tapText(tester, 'Nail');
    await tapText(tester, 'Me');
    app.container.read(checkFlowProvider.notifier).setPhoto(testPhoto());
    await tester.pumpAndSettle();
    await tapText(tester, 'Continue');
    // Skip optional questions; otherwise answer "None of these" or "Not
    // sure".
    for (var i = 0; i < 12; i++) {
      if (find.text('Anything else we should know?').evaluate().isNotEmpty) {
        break;
      }
      if (find.text('Skip').hitTestable().evaluate().isNotEmpty) {
        await tapText(tester, 'Skip');
        continue;
      }
      final multi = find.text('Select all that apply.').evaluate().isNotEmpty;
      final answer = await scrollToText(tester, 'None of these')
          ? 'None of these'
          : 'Not sure';
      await tapText(tester, answer);
      if (multi) {
        await tapText(tester, 'Next');
      } else {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
      }
    }
    await tapText(tester, 'Analyze');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text("We couldn't finish the analysis"), findsOneWidget);
    expect(find.text('SpotCheck is very busy right now.'), findsOneWidget);
    expect(app.container.read(historyProvider), isEmpty);
    expect(
      app.container.read(settingsProvider).checksUsed,
      0,
      reason: 'failed checks are free',
    );
  });
}
