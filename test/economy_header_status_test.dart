import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/core/cache/cached.dart';
import 'package:peerkola/src/core/settings/app_settings.dart'
    show sharedPreferencesProvider;
import 'package:peerkola/src/features/economy/application/economy_providers.dart';
import 'package:peerkola/src/features/economy/data/economy.dart';
import 'package:peerkola/src/features/economy/presentation/economy_header_status.dart';

/// The economy moved out of a full-width bar and into the app bar, which lays
/// its actions out with `CrossAxisAlignment.stretch` — so "does it still look
/// like a pill up there?" is the thing worth pinning down, along with the two
/// numbers it states.
void main() {
  Future<void> pumpPill(
    WidgetTester tester, {
    required EconomyBarVariant variant,
    required int balance,
    required int price,
    Economy? economy,
    Locale? locale,
  }) async {
    // The pill opens the explainer sheet, which carries the channel-price
    // switch and therefore reads preferences — overridden in `main()` in the
    // real app, so it has to be here too.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          economyProvider.overrideWith(
            () => _FakeEconomyNotifier(
              economy ?? Economy(tokenBalance: balance, postPrice: price),
            ),
          ),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Feed'),
              actions: [
                EconomyHeaderStatus(variant: variant),
                IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the pill keeps its own height inside an app bar', (
    tester,
  ) async {
    await pumpPill(
      tester,
      variant: EconomyBarVariant.feed,
      balance: 12,
      price: 3,
    );

    // Stretched, it would be as tall as the toolbar (56) and read as a lozenge.
    final pill = tester.getSize(
      find.ancestor(
        of: find.byIcon(Icons.toll_outlined),
        matching: find.byType(InkWell),
      ),
    );
    expect(pill.height, lessThan(40));
  });

  testWidgets('the feed states the balance and what it is short of', (
    tester,
  ) async {
    await pumpPill(
      tester,
      variant: EconomyBarVariant.feed,
      balance: 1,
      price: 3,
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2 more tokens to post'), findsOneWidget);
    expect(
      find.text('3'),
      findsNothing,
      reason: 'the price is the bar, not a number',
    );
  });

  testWidgets('the composer states what this post costs, not the balance', (
    tester,
  ) async {
    await pumpPill(
      tester,
      variant: EconomyBarVariant.composer,
      balance: 12,
      price: 3,
    );

    // Named, not signed: "Cost 3" rather than the old "−3", which read as a
    // balance change beside a feed pill that states a bare balance.
    expect(find.text('Cost'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // No expiry on this quote (an old cached one), so the clause falls back to
    // the balance rather than counting down from nothing.
    expect(find.text('of your 12'), findsOneWidget);
    expect(find.text('12'), findsNothing, reason: 'the cost is the headline');
  });

  testWidgets('the composer counts the price-lock window down', (tester) async {
    await pumpPill(
      tester,
      variant: EconomyBarVariant.composer,
      balance: 12,
      price: 3,
      economy: Economy(
        tokenBalance: 12,
        postPrice: 3,
        postPriceExpiresAt: DateTime.now().add(
          const Duration(minutes: 2, seconds: 31),
        ),
      ),
    );

    expect(find.text('held for 2:30'), findsOneWidget);
    // The tick re-derives the remaining time from `DateTime.now()`, which the
    // test clock doesn't move — so this pumps the timer for its own sake, to
    // catch a rebuild that throws rather than a decremented digit.
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('held for'), findsOneWidget);
  });

  testWidgets('an unaffordable price states the shortfall, not the clock', (
    tester,
  ) async {
    await pumpPill(
      tester,
      variant: EconomyBarVariant.composer,
      balance: 1,
      price: 3,
      economy: Economy(
        tokenBalance: 1,
        postPrice: 3,
        postPriceExpiresAt: DateTime.now().add(const Duration(minutes: 2)),
      ),
    );

    expect(find.text('2 more needed'), findsOneWidget);
  });

  testWidgets('a long label is capped, not left to push the title off screen', (
    tester,
  ) async {
    // A small phone in the longest of the two locales: "Noch 999 Token bis zum
    // Posten" alongside a title and a reload button.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpPill(
      tester,
      variant: EconomyBarVariant.feed,
      balance: 0,
      price: 999,
      locale: const Locale('de'),
    );

    final pill = tester.getRect(
      find.ancestor(
        of: find.byIcon(Icons.toll_outlined),
        matching: find.byType(InkWell),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(pill.right, lessThanOrEqualTo(320));
    expect(pill.width, lessThan(320 * 0.7));
  });

  testWidgets('tapping opens the explainer, with the live figures', (
    tester,
  ) async {
    await pumpPill(
      tester,
      variant: EconomyBarVariant.feed,
      balance: 12,
      price: 3,
    );

    await tester.tap(find.byType(EconomyHeaderStatus));
    await tester.pumpAndSettle();

    expect(find.text('How posting works'), findsOneWidget);
    expect(find.text('You have 12 tokens'), findsOneWidget);
    expect(find.text('A post costs 3 tokens right now'), findsOneWidget);
  });

  testWidgets('an expired quote is re-fetched from the composer', (
    tester,
  ) async {
    final notifier = _FakeEconomyNotifier(
      Economy(
        tokenBalance: 12,
        postPrice: 3,
        postPriceExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [economyProvider.overrideWith(() => notifier)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            appBar: AppBar(
              actions: const [
                EconomyHeaderStatus(variant: EconomyBarVariant.composer),
              ],
            ),
          ),
        ),
      ),
    );
    // Not pumpAndSettle: the checking state renders a spinner, and an
    // indeterminate progress indicator never settles.
    await tester.pump();

    expect(notifier.refreshCount, 1);
    // The clause it replaces is gone, and the sentence is on the tooltip.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('checking'), findsNothing);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'checking price…',
    );
  });

  group('price range', () {
    // There is no single price any more — every (channel, language) route is
    // priced by its own congestion — so both pills have to be able to state a
    // spread. The failure this guards is silent: showing one plausible number
    // where a range was meant looks completely normal on screen.
    testWidgets('the composer states a range before a route is chosen', (
      tester,
    ) async {
      await pumpPill(
        tester,
        variant: EconomyBarVariant.composer,
        balance: 20,
        price: 4,
        economy: const Economy(
          tokenBalance: 20,
          postPrice: 4,
          postPriceMin: 2,
          postPriceMax: 6,
        ),
      );

      expect(find.text('2–6'), findsOneWidget);
      expect(
        find.text('4'),
        findsNothing,
        reason: 'the base rate is not a price anyone pays',
      );
    });

    testWidgets('the composer narrows to one number once the route is known', (
      tester,
    ) async {
      // What the composer does after a channel and a language are picked: it
      // collapses the range onto the exact quote, which is also the number the
      // Publish button is gated on.
      await pumpPill(
        tester,
        variant: EconomyBarVariant.composer,
        balance: 20,
        price: 4,
        economy: const Economy(
          tokenBalance: 20,
          postPrice: 4,
          postPriceMin: 4,
          postPriceMax: 4,
        ),
      );

      expect(find.text('4'), findsOneWidget);
      expect(find.text('4–4'), findsNothing, reason: 'reads as a bug');
    });

    testWidgets('the feed pill says what posts cost', (tester) async {
      // It used to say "Enough to post", which named no number the reader could
      // act on — and there is no longer one price to go and look up elsewhere.
      await pumpPill(
        tester,
        variant: EconomyBarVariant.feed,
        balance: 20,
        price: 4,
        economy: const Economy(
          tokenBalance: 20,
          postPrice: 4,
          postPriceMin: 2,
          postPriceMax: 6,
        ),
      );

      // Phrased as a rate, and separated from the balance by a middot: led
      // with the noun ("Posts cost 2–6") it ran straight on from the number
      // before it and read as a sentence about twenty posts.
      expect(find.text('2–6 tokens per post'), findsOneWidget);
      expect(find.text('20'), findsOneWidget, reason: 'the balance stays');
      expect(find.text('·'), findsOneWidget);
    });

    testWidgets('a shortfall still counts to the cheapest route', (
      tester,
    ) async {
      // "3 more needed" has to mean "to post anywhere". Counting up to the
      // dearest route would keep refusing someone who could already publish.
      await pumpPill(
        tester,
        variant: EconomyBarVariant.feed,
        balance: 1,
        price: 6,
        economy: const Economy(
          tokenBalance: 1,
          postPrice: 6,
          postPriceMin: 4,
          postPriceMax: 6,
        ),
      );

      expect(find.text('3 more tokens to post'), findsOneWidget);
    });
  });
}

class _FakeEconomyNotifier extends EconomyNotifier {
  _FakeEconomyNotifier(this.economy);

  final Economy economy;
  int refreshCount = 0;

  @override
  Cached<Economy>? build() => Cached.live(economy);

  @override
  Future<void> refresh() async => refreshCount++;
}
