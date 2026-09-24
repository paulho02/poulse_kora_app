import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/core/cache/cached.dart';
import 'package:peerkola/src/core/languages/language_providers.dart';
import 'package:peerkola/src/features/channels/application/channels_providers.dart';
import 'package:peerkola/src/features/channels/data/channel.dart';
import 'package:peerkola/src/features/onboarding/presentation/content_languages_step.dart';
import 'package:peerkola/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:peerkola/src/features/profile/application/profile_providers.dart';
import 'package:peerkola/src/features/profile/data/user_profile.dart';

/// The backend narrows a new account to the locale its registration request
/// carried, so a German phone produces a German-only reader. That default is
/// invisible from inside the app: the setting has a home in the Filters tab,
/// but nothing pointed a new account at it, and a feed filtered down to one
/// language just looks like a platform with nothing on it.
///
/// What is pinned here is therefore the *surfacing*, not the editing — that is
/// `feed_preferences_test.dart`'s, since both screens now drive the same
/// `ContentLanguageChecklist`. This file asks: does the flow reach the step,
/// does the step say where the ticks came from, and can someone who is happy
/// with the default walk past it.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  ProviderContainer containerFor(_FakeProfile profile) {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        // Overridden rather than left to `appConfigProvider`'s fallback, so the
        // list under test is a stated fixture instead of whatever a failed
        // config fetch happens to degrade to.
        contentLanguagesProvider.overrideWithValue(const ['en', 'de']),
        channelsNotifierProvider.overrideWith(_FakeChannels.new),
        profileProvider.overrideWith(() => profile),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpIn(
    WidgetTester tester,
    ProviderContainer container,
    Widget child,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
    // Not `pumpAndSettle` when the whole flow is mounted: the intro slides'
    // icon badge animates on a loop, so nothing here ever settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('ContentLanguagesStep', () {
    testWidgets('says where the ticks came from, not just that they are there', (
      tester,
    ) async {
      // The point of the step. Ticked boxes with no explanation read as a
      // choice the reader made, and there is then nothing to react to.
      final container = containerFor(_FakeProfile(const ['de']));
      await pumpIn(
        tester,
        container,
        Scaffold(body: ContentLanguagesStep(onContinue: () {})),
      );

      expect(find.text(l10n.onboardingLanguagesTitle), findsOneWidget);
      expect(find.text(l10n.onboardingLanguagesDefaultNote), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      expect(_checkbox(tester, 'German').value, isTrue);
      expect(_checkbox(tester, 'English').value, isFalse);
    });

    testWidgets('lets someone happy with the default walk straight past', (
      tester,
    ) async {
      // Unlike the channel step before it, this one never blocks: registration
      // guarantees a non-empty set, so there is always a valid answer already
      // on screen and passing through is a legitimate one.
      var continued = false;
      final profile = _FakeProfile(const ['de']);
      final container = containerFor(profile);
      await pumpIn(
        tester,
        container,
        Scaffold(
          body: ContentLanguagesStep(onContinue: () => continued = true),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, l10n.commonContinue));
      await tester.pump();

      expect(continued, isTrue);
      expect(profile.pushed, isEmpty, reason: 'nothing was changed');
    });

    testWidgets('widening pushes the whole set, with no Save button', (
      tester,
    ) async {
      final profile = _FakeProfile(const ['de']);
      final container = containerFor(profile);
      await pumpIn(
        tester,
        container,
        Scaffold(body: ContentLanguagesStep(onContinue: () {})),
      );

      await tester.tap(find.text('English'));
      await tester.pump();

      expect(profile.pushed, [
        ['de', 'en'],
      ]);
      expect(_checkbox(tester, 'English').value, isTrue);
    });

    testWidgets('refuses to leave the reader with no language at all', (
      tester,
    ) async {
      final profile = _FakeProfile(const ['de']);
      final container = containerFor(profile);
      await pumpIn(
        tester,
        container,
        Scaffold(body: ContentLanguagesStep(onContinue: () {})),
      );

      await tester.tap(find.text('German'));
      await tester.pump();

      expect(profile.pushed, isEmpty);
      expect(find.text(l10n.settingsContentLanguagesEmpty), findsOneWidget);
    });
  });

  group('OnboardingScreen', () {
    testWidgets('reaches the languages step on the way to the disclaimer', (
      tester,
    ) async {
      final container = containerFor(_FakeProfile(const ['de']));
      await pumpIn(tester, container, const OnboardingScreen());

      await tester.tap(find.text(l10n.onboardingSkip));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(l10n.tutorialOfferDecline));
      await tester.pump(const Duration(milliseconds: 400));

      // The fixture channel is already subscribed, so the channel step's own
      // 1-3 gate is satisfied and Continue is live.
      expect(find.text(l10n.onboardingChannelsTitle), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, l10n.commonContinue));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(l10n.onboardingLanguagesTitle), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, l10n.commonContinue));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(l10n.onboardingDisclaimerTitle), findsOneWidget);
    });

    testWidgets('a replay never reaches it', (tester) async {
      // Settings' "Replay intro" is the intro, not a second pass at settings
      // that have had a permanent home in Filters ever since.
      final container = containerFor(_FakeProfile(const ['de']));
      await pumpIn(tester, container, const OnboardingScreen(isReplay: true));

      await tester.tap(find.text(l10n.onboardingSkip));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(l10n.onboardingLanguagesTitle), findsNothing);
      expect(find.text(l10n.onboardingDisclaimerTitle), findsOneWidget);
    });
  });
}

CheckboxListTile _checkbox(WidgetTester tester, String label) {
  return tester.widget<CheckboxListTile>(
    find.ancestor(
      of: find.text(label),
      matching: find.byType(CheckboxListTile),
    ),
  );
}

class _FakeChannels extends ChannelsNotifier {
  @override
  Future<Cached<List<Channel>>> build() async => Cached.live([
    Channel(
      id: 1,
      name: 'Technology',
      color: '#2563EB',
      description: 'Tech talk',
      isSubscribed: true,
      postPriceMin: 3,
      postPriceMax: 3,
    ),
  ]);
}

/// Records what reached the server, and applies it locally the way the real
/// notifier does — the checkbox is driven by the profile, never by local state,
/// so a push that never happened must leave the tick where it was.
class _FakeProfile extends ProfileNotifier {
  _FakeProfile(this.initial);

  final List<String> initial;
  final pushed = <List<String>>[];

  @override
  Future<Cached<UserProfile>> build() async => Cached.live(_profile(initial));

  @override
  Future<void> setContentLanguages(List<String> languages) async {
    pushed.add(List.of(languages));
    state = AsyncData(Cached.live(_profile(languages)));
  }

  UserProfile _profile(List<String> languages) => UserProfile.fromJson({
    'id': 'u1',
    'email': 'a@b.c',
    'username': 'someone',
    'bio': null,
    'dark_mode': false,
    'is_verified': true,
    'profile_picture_url': null,
    'content_languages': languages,
  });
}
