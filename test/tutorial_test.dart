import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/features/onboarding/presentation/tutorial_offer_step.dart';
import 'package:peerkola/src/features/tutorial/presentation/tutorial_deck.dart';

/// The tutorial deck and the onboarding offer in front of it.
///
/// Note the complete absence of `pumpAndSettle`: the visible chapter's
/// illustration loops forever, so settling never happens and every call would
/// time out after ten minutes of frames. `pump(duration)` is the only way to
/// drive anything containing one of these, and that is worth failing loudly
/// about rather than rediscovering in a future test.
void main() {
  Widget host(Widget child, {Locale? locale}) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  /// One frame to let the tap schedule the page animation, then one long
  /// enough to land it — short enough not to sit through hundreds of frames of
  /// a looping painter.
  Future<void> advance(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('TutorialDeck', () {
    testWidgets('walks all five chapters and finishes on the last', (
      tester,
    ) async {
      var finished = 0;
      await tester.pumpWidget(
        host(TutorialDeck(onFinish: () => finished++)),
      );
      await advance(tester);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.tutorialChapter1Title), findsOneWidget);
      expect(find.text(l10n.tutorialStepCounter(1, 5)), findsOneWidget);

      // Four taps of "Next" to reach the end; the fifth confirms.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text(l10n.tutorialNext));
        await advance(tester);
      }
      expect(find.text(l10n.tutorialChapter5Title), findsOneWidget);
      expect(find.text(l10n.tutorialStepCounter(5, 5)), findsOneWidget);
      expect(finished, 0);

      await tester.tap(find.text(l10n.tutorialDone));
      await advance(tester);
      expect(finished, 1);
    });

    testWidgets('offers no skip unless one is wired', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // The Settings route relies on this: its app bar is the way out, and a
      // second one a line below would be noise.
      await tester.pumpWidget(host(TutorialDeck(onFinish: () {})));
      await advance(tester);
      expect(find.text(l10n.tutorialSkip), findsNothing);

      var skipped = 0;
      await tester.pumpWidget(
        host(TutorialDeck(onFinish: () {}, onSkip: () => skipped++)),
      );
      await advance(tester);
      await tester.tap(find.text(l10n.tutorialSkip));
      await advance(tester);
      expect(skipped, 1);
    });

    testWidgets('shows the footnote only on the last chapter', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.pumpWidget(
        host(
          TutorialDeck(
            onFinish: () {},
            footnote: l10n.tutorialSettingsHint,
          ),
        ),
      );
      await advance(tester);
      expect(find.text(l10n.tutorialSettingsHint), findsNothing);

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text(l10n.tutorialNext));
        await advance(tester);
      }
      expect(find.text(l10n.tutorialSettingsHint), findsOneWidget);
    });

    testWidgets('is fully translated', (tester) async {
      final de = await AppLocalizations.delegate.load(const Locale('de'));
      await tester.pumpWidget(
        host(TutorialDeck(onFinish: () {}), locale: const Locale('de')),
      );
      await advance(tester);
      expect(find.text(de.tutorialChapter1Title), findsOneWidget);
      expect(find.text(de.tutorialNext), findsOneWidget);
    });
  });

  group('TutorialOfferStep', () {
    testWidgets('both answers are offered, and both are answers', (
      tester,
    ) async {
      var accepted = 0;
      var declined = 0;
      await tester.pumpWidget(
        host(
          TutorialOfferStep(
            onAccept: () => accepted++,
            onDecline: () => declined++,
          ),
        ),
      );
      await advance(tester);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // The hint that this is re-openable belongs on the screen where it can
      // be turned down, not only at the end of a deck the decliner never sees.
      expect(find.text(l10n.tutorialSettingsHint), findsOneWidget);

      await tester.tap(find.text(l10n.tutorialOfferDecline));
      await advance(tester);
      expect(declined, 1);
      expect(accepted, 0);

      await tester.tap(find.text(l10n.tutorialOfferAccept));
      await advance(tester);
      expect(accepted, 1);
    });
  });
}
