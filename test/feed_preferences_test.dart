import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/core/cache/cached.dart';
import 'package:peerkola/src/core/settings/app_settings.dart'
    show sharedPreferencesProvider;
import 'package:peerkola/src/features/channels/application/channels_providers.dart';
import 'package:peerkola/src/features/channels/data/channel.dart';
import 'package:peerkola/src/features/economy/application/economy_providers.dart';
import 'package:peerkola/src/features/economy/data/economy.dart';
import 'package:peerkola/src/features/feed_preferences/presentation/feed_preferences_screen.dart';
import 'package:peerkola/src/features/profile/application/profile_providers.dart';
import 'package:peerkola/src/features/profile/data/user_profile.dart';

/// Channels and accepted languages are the same kind of thing — filters applied
/// before a post ever reaches your queue — so they live behind one screen. The
/// language half used to sit in Settings next to the app's *interface*
/// language, where the two read as one setting stated twice.
void main() {
  Future<void> pumpPrefs(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          channelsNotifierProvider.overrideWith(_FakeChannels.new),
          economyProvider.overrideWith(
            () => _FakeEconomy(const Economy(tokenBalance: 7, postPrice: 3)),
          ),
          profileProvider.overrideWith(_FakeProfile.new),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const FeedPreferencesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers both filters as tabs under one generic title', (
    tester,
  ) async {
    await pumpPrefs(tester);

    expect(find.text('Filters'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Channels'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Languages'), findsOneWidget);
  });

  testWidgets('opens on channels', (tester) async {
    await pumpPrefs(tester);
    expect(find.text('General'), findsOneWidget);
  });

  testWidgets('the languages tab edits which languages are accepted', (
    tester,
  ) async {
    await pumpPrefs(tester);
    await tester.tap(find.widgetWithText(Tab, 'Languages'));
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    // The disambiguation still has to be here: Settings keeps a language row of
    // its own, and nothing else says the two are different questions.
    expect(
      find.textContaining("separate from the app's own language"),
      findsOneWidget,
    );
  });

  testWidgets('the price switch belongs to the channel list alone', (
    tester,
  ) async {
    // It is chrome about the channel rows. Left in the bar unconditionally it
    // would sit over the languages tab as a control with no subject.
    await pumpPrefs(tester);
    expect(find.byType(Switch), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Languages'));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('the channel tab can be searched', (tester) async {
    await pumpPrefs(tester);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Sports'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'spo');
    await tester.pumpAndSettle();

    expect(find.text('Sports'), findsOneWidget);
    expect(find.text('General'), findsNothing);
  });

  testWidgets('the language tab can be searched', (tester) async {
    await pumpPrefs(tester);
    await tester.tap(find.widgetWithText(Tab, 'Languages'));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    expect(find.text('German'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ger');
    await tester.pumpAndSettle();

    expect(find.text('German'), findsOneWidget);
    expect(find.text('English'), findsNothing);
  });

  testWidgets('a language search with no match says so, not nothing', (
    tester,
  ) async {
    await pumpPrefs(tester);
    await tester.tap(find.widgetWithText(Tab, 'Languages'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'xyz');
    await tester.pumpAndSettle();

    expect(find.text('No languages found'), findsOneWidget);
  });

  testWidgets(
    'one tip explains both tabs, rather than one per tab left unintroduced',
    (tester) async {
      await pumpPrefs(tester);

      // Describes the *screen's* purpose, true on either tab, not one tab's
      // mechanics — so it has to mention both channels and languages.
      expect(
        find.textContaining('Channels and languages both shape your Feed'),
        findsOneWidget,
      );

      // Dismissing it is a screen-level fact, not a per-tab one: switching
      // tabs must not bring back a card the reader already closed.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Channels and languages both shape your Feed'),
        findsNothing,
      );

      await tester.tap(find.widgetWithText(Tab, 'Languages'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Channels and languages both shape your Feed'),
        findsNothing,
      );
    },
  );
}

class _FakeEconomy extends EconomyNotifier {
  _FakeEconomy(this.economy);
  final Economy economy;

  @override
  Cached<Economy>? build() => Cached.live(economy);

  @override
  Future<void> refresh() async {}

  @override
  Future<void> ensureLoaded() async {}
}

class _FakeChannels extends ChannelsNotifier {
  @override
  Future<Cached<List<Channel>>> build() async => Cached.live([
    Channel(
      id: 1,
      name: 'General',
      color: '#6B7280',
      description: 'Everything',
      isSubscribed: true,
      postPriceMin: 3,
      postPriceMax: 3,
    ),
    Channel(
      id: 2,
      name: 'Sports',
      color: '#22C55E',
      description: 'Scores and matches',
      isSubscribed: false,
      postPriceMin: 3,
      postPriceMax: 3,
    ),
  ]);
}

class _FakeProfile extends ProfileNotifier {
  @override
  Future<Cached<UserProfile>> build() async => Cached.live(
    UserProfile.fromJson(const {
      'id': 'u1',
      'email': 'a@b.c',
      'username': 'someone',
      'bio': null,
      'dark_mode': false,
      'is_verified': true,
      'profile_picture_url': null,
      'content_languages': ['en'],
    }),
  );
}
