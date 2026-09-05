import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/l10n/generated/app_localizations.dart';
import 'package:poulse_kora_app/src/core/cache/cached.dart';
import 'package:poulse_kora_app/src/core/settings/app_settings.dart'
    show sharedPreferencesProvider;
import 'package:poulse_kora_app/src/features/economy/application/economy_providers.dart';
import 'package:poulse_kora_app/src/features/economy/data/economy.dart';
import 'package:poulse_kora_app/src/features/economy/presentation/economy_header_status.dart';

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

    expect(find.text('−3'), findsOneWidget);
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
    await tester.pumpAndSettle();

    expect(notifier.refreshCount, 1);
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
