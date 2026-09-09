import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/l10n/generated/app_localizations.dart';
import 'package:poulse_kora_app/src/core/cache/cached.dart';
import 'package:poulse_kora_app/src/core/settings/app_settings.dart'
    show sharedPreferencesProvider;
import 'package:poulse_kora_app/src/core/settings/price_display_settings.dart';
import 'package:poulse_kora_app/src/features/channels/application/channels_providers.dart';
import 'package:poulse_kora_app/src/features/channels/data/channel.dart';
import 'package:poulse_kora_app/src/features/channels/presentation/channel_avatar.dart';
import 'package:poulse_kora_app/src/features/channels/presentation/channel_price_chip.dart';
import 'package:poulse_kora_app/src/features/channels/presentation/channels_screen.dart';
import 'package:poulse_kora_app/src/features/economy/application/economy_providers.dart';
import 'package:poulse_kora_app/src/features/economy/data/economy.dart';
import 'package:poulse_kora_app/src/features/economy/presentation/economy_explainer.dart';

/// The channel row stacks a price under the badge and sits in a card, and the
/// explainer became a full-screen route. Both are layouts that fail by
/// *overflowing* rather than by throwing — a red-and-yellow band in a corner of
/// one screen, which no other test in this suite would notice and which is
/// invisible to `flutter analyze`.
///
/// A widget test does notice: an unsatisfied constraint is an exception, so
/// pumping these at a small screen and at a large text scale is the check.
void main() {
  final channels = [
    Channel(
      id: 1,
      name: 'Technology',
      color: '#2563EB',
      description: 'Tech talk, hardware and software',
      isSubscribed: false,
      postPrice: 3,
    ),
    Channel(
      id: 2,
      name: 'Outdoors',
      color: '#16A34A',
      description: 'Hiking, climbing and everything outside',
      isSubscribed: true,
      postPrice: 12,
    ),
  ];

  Future<void> pumpChannels(
    WidgetTester tester, {
    required bool showPrices,
    double textScale = 1.0,
    Size size = const Size(360, 640),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          channelsNotifierProvider.overrideWith(() => _FakeChannels(channels)),
          economyProvider.overrideWith(
            () => _FakeEconomy(
              const Economy(tokenBalance: 7, postPrice: 5),
            ),
          ),
          showChannelPricesProvider.overrideWith(
            () => _FakeShowPrices(showPrices),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const ChannelsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the channel row lays out with prices on', (tester) async {
    await pumpChannels(tester, showPrices: true);

    expect(find.byType(ChannelAvatar), findsNWidgets(2));
    // The channel's own price, under its badge.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a channel is drawn by an icon, never by its initial', (
    tester,
  ) async {
    // The letter-on-a-disc read as a contact list. A topic is not a person.
    await pumpChannels(tester, showPrices: false);

    expect(find.byType(ChannelAvatar), findsNWidgets(2));
    expect(find.text('T'), findsNothing);
    expect(find.text('O'), findsNothing);
  });

  testWidgets('the row survives a large text scale on a small screen', (
    tester,
  ) async {
    // The case the old three-line ListTile handled worst, and the one a card
    // with a stacked leading column is most likely to break.
    await pumpChannels(tester, showPrices: true, textScale: 1.6);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the price switch is a labelled switch in the app bar', (
    tester,
  ) async {
    await pumpChannels(tester, showPrices: false);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // A real switch with a word beside it, not the `isSelected` coin glyph it
    // replaced — and in the header, not spending a full row over the list.
    expect(find.text(l10n.channelsShowPricesLabel), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.byType(Switch)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.toll), findsNothing);
  });

  testWidgets('the price chip is drawn as a control, not as a caption', (
    tester,
  ) async {
    // A bare number under an avatar reads as a caption and invites no tap. The
    // border is the whole affordance, so its absence is worth failing on.
    await pumpChannels(tester, showPrices: true);

    final chip = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(ChannelPriceChip),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(chip.shape, isA<StadiumBorder>());
    expect((chip.shape! as StadiumBorder).side.style, BorderStyle.solid);
  });

  testWidgets('the explainer takes the whole screen and scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          economyProvider.overrideWith(
            () => _FakeEconomy(const Economy(tokenBalance: 7, postPrice: 5)),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showEconomyExplainer(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.economyExplainerTitle), findsOneWidget);
    // A full-screen route, not a sheet capped at a fraction of the height.
    final page = tester.getSize(find.byType(Scaffold).last);
    expect(page.height, 640);
    expect(tester.takeException(), isNull);
  });
}

class _FakeChannels extends ChannelsNotifier {
  _FakeChannels(this.channels);

  final List<Channel> channels;

  @override
  Future<Cached<List<Channel>>> build() async => Cached.live(channels);
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

class _FakeShowPrices extends ShowChannelPricesNotifier {
  _FakeShowPrices(this.initial);

  final bool initial;

  @override
  bool build() => initial;

  @override
  Future<void> set(bool value) async => state = value;
}
