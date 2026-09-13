import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/l10n/generated/app_localizations.dart';
import 'package:poulse_kora_app/src/core/cache/cached.dart';
import 'package:poulse_kora_app/src/core/settings/app_settings.dart'
    show sharedPreferencesProvider;
import 'package:poulse_kora_app/src/features/channels/application/channels_providers.dart';
import 'package:poulse_kora_app/src/features/channels/data/channel.dart';
import 'package:poulse_kora_app/src/features/create_post/presentation/create_post_screen.dart';
import 'package:poulse_kora_app/src/features/economy/application/economy_providers.dart';
import 'package:poulse_kora_app/src/features/economy/data/economy.dart';

/// The composer's language chip is filled in by the on-device detector as the
/// author types. That wiring is easy to break without noticing — a controller
/// created down a path that forgot to attach the listener, a debounce that
/// never fires — and the symptom is silence, not an error. So this drives the
/// real screen rather than the detector.
void main() {
  Future<void> pumpComposer(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          economyProvider.overrideWith(
            () => _FakeEconomy(const Economy(tokenBalance: 20, postPrice: 3)),
          ),
          channelsNotifierProvider.overrideWith(_FakeChannels.new),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CreatePostScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('typing German fills the language chip in', (tester) async {
    await pumpComposer(tester);
    expect(find.text('Language'), findsOneWidget, reason: 'starts unset');

    await tester.enterText(
      find.byType(TextField).first,
      'Das ist ein Test um zu sehen ob die Erkennung geht',
    );
    // Past the detector's debounce.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('German'), findsOneWidget);
    expect(find.text('Language'), findsNothing);
  });

  testWidgets('a short sentence is enough', (tester) async {
    // The threshold that matters in practice: a first post is usually one
    // short line, and abstaining on it reads as the feature being broken.
    await pumpComposer(tester);

    await tester.enterText(find.byType(TextField).first, 'Das ist ein Test');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('German'), findsOneWidget);
  });

  testWidgets('switching language mid-draft follows the text', (tester) async {
    await pumpComposer(tester);

    await tester.enterText(find.byType(TextField).first, 'This is a test');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('removing a block re-decides from what is left', (tester) async {
    // The bug this pins: detection ran off a controller listener, so deleting
    // a paragraph fired nothing and the suggestion stayed on a language the
    // post no longer contained. It has to be a function of the current text,
    // not of what was typed most recently.
    await pumpComposer(tester);

    await tester.enterText(
      find.byType(TextField).first,
      'Das ist ein deutscher Absatz und der bleibt erstmal so stehen',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('German'), findsOneWidget);

    // A second paragraph, in English, added below it.
    await tester.tap(find.byIcon(Icons.notes_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(1),
      'And this one is written in English so that it can be told apart',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    // Now delete the German paragraph. Nothing types, nothing changes focus —
    // only the set of blocks changes. By tooltip, not by `Icons.close`: the
    // composer's own tip card carries one of those too, and tapping it would
    // dismiss the tip while leaving both paragraphs in place.
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();

    expect(find.text('English'), findsOneWidget);
    expect(find.text('German'), findsNothing);
  });

  testWidgets('deleting all the text withdraws the suggestion', (tester) async {
    // Not the same as "not confident": there is no text at all, so the earlier
    // answer describes a post that no longer exists. Withdrawing it is also
    // what puts "no language" back within reach for a photo-only post.
    await pumpComposer(tester);

    await tester.enterText(find.byType(TextField).first, 'Das ist ein Test');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('German'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('German'), findsNothing);
    expect(find.text('Language'), findsOneWidget);
  });

  testWidgets('the language chip is on screen without scrolling', (
    tester,
  ) async {
    // It used to sit in a horizontal scroller beside the channel chip, which on
    // a phone put it past the right edge. A required control that has to be
    // scrolled into view is one nobody knows is there — and this one is
    // required, so the composer refused to publish over something invisible.
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpComposer(tester);

    final chip = find.text('Language');
    expect(chip, findsOneWidget);
    final rect = tester.getRect(chip);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
  });
}

class _FakeEconomy extends EconomyNotifier {
  _FakeEconomy(this.economy);
  final Economy economy;

  @override
  Cached<Economy>? build() => Cached.live(economy);

  @override
  Future<void> refresh() async {}
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
  ]);
}
