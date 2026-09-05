import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/l10n/generated/app_localizations.dart';
import 'package:poulse_kora_app/src/core/cache/cached.dart';
import 'package:poulse_kora_app/src/features/channels/data/channel.dart';
import 'package:poulse_kora_app/src/features/channels/presentation/channel_price_label.dart';
import 'package:poulse_kora_app/src/features/economy/application/economy_providers.dart';
import 'package:poulse_kora_app/src/features/economy/data/economy.dart';
import 'package:poulse_kora_app/src/features/economy/presentation/economy_header_status.dart';

/// Posting is priced per channel, and two things about that would break
/// quietly rather than loudly.
///
/// The first is the composer charging one number while showing another: the
/// backend quotes and charges the *channel's* price, but `GET /posts/economy`
/// returns the global reference rate, so a composer that forgot the override
/// would show a price nobody is ever charged — and it would look completely
/// normal on screen.
///
/// The second is a missing price being read as a free one. `postPrice` is
/// nullable for channel lists cached before per-channel pricing existed, and
/// `0` is a perfectly plausible-looking token count.
void main() {
  Channel channel({int? postPrice}) => Channel(
    id: 1,
    name: 'Music',
    color: '#ff0000',
    description: 'Songs',
    isSubscribed: true,
    postPrice: postPrice,
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required int balance,
    required int globalPrice,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          economyProvider.overrideWith(
            () => _FakeEconomyNotifier(
              Economy(tokenBalance: balance, postPrice: globalPrice),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            appBar: AppBar(title: const Text('Channels'), actions: [child]),
            body: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ChannelPriceLabel', () {
    testWidgets('resolves the price into whether it can be afforded', (
      tester,
    ) async {
      await pump(
        tester,
        ChannelPriceLabel(channel: channel(postPrice: 3)),
        balance: 12,
        globalPrice: 5,
      );

      // The channel's price, not the global one, and the clause that answers
      // the only question being asked of it.
      expect(find.text('3'), findsWidgets);
      expect(find.text('Enough to post'), findsWidgets);
    });

    testWidgets('states the shortfall rather than just the price', (
      tester,
    ) async {
      await pump(
        tester,
        ChannelPriceLabel(channel: channel(postPrice: 10)),
        balance: 4,
        globalPrice: 5,
      );

      expect(find.text('10'), findsWidgets);
      expect(find.text('6 more tokens to post'), findsWidgets);
    });

    testWidgets('renders nothing when the price is unknown', (tester) async {
      await pump(
        tester,
        ChannelPriceLabel(channel: channel()),
        balance: 12,
        globalPrice: 5,
      );

      expect(find.byIcon(Icons.toll_outlined), findsNothing);
      expect(find.text('Enough to post'), findsNothing);
    });
  });

  group('composer pill', () {
    testWidgets('prices the post from the chosen channel, not the global rate', (
      tester,
    ) async {
      await pump(
        tester,
        const EconomyHeaderStatus(
          variant: EconomyBarVariant.composer,
          priceOverride: 7,
        ),
        balance: 20,
        globalPrice: 3,
      );

      expect(find.text('−7'), findsWidgets);
      expect(find.text('−3'), findsNothing);
    });

    testWidgets('falls back to the global rate before a channel is chosen', (
      tester,
    ) async {
      await pump(
        tester,
        const EconomyHeaderStatus(variant: EconomyBarVariant.composer),
        balance: 20,
        globalPrice: 3,
      );

      expect(find.text('−3'), findsWidgets);
    });

    testWidgets('an unaffordable channel price drives the short state', (
      tester,
    ) async {
      // Affordable at the global rate, not at this channel's — the case that
      // would let someone press Relay into a 402 if the override were dropped.
      await pump(
        tester,
        const EconomyHeaderStatus(
          variant: EconomyBarVariant.composer,
          priceOverride: 9,
        ),
        balance: 4,
        globalPrice: 3,
      );

      expect(find.text('5 more needed'), findsWidgets);
    });
  });

  group('Channel.fromJson', () {
    test('reads the quoted price', () {
      final parsed = Channel.fromJson(const {
        'id': 1,
        'name': 'Music',
        'color': '#ff0000',
        'description': 'Songs',
        'is_subscribed': true,
        'post_price': 4,
      });
      expect(parsed.postPrice, 4);
    });

    test('leaves the price unknown when the payload predates it', () {
      final parsed = Channel.fromJson(const {
        'id': 1,
        'name': 'Music',
        'color': '#ff0000',
        'description': 'Songs',
        'is_subscribed': true,
      });
      expect(parsed.postPrice, isNull);
    });

    test('carries the price through a subscription toggle', () {
      // `copyWith` is how an optimistic subscribe rebuilds the row; dropping
      // the price there would blank the label mid-tap.
      final toggled = channel(postPrice: 4).copyWith(isSubscribed: false);
      expect(toggled.postPrice, 4);
    });
  });
}

class _FakeEconomyNotifier extends EconomyNotifier {
  _FakeEconomyNotifier(this.economy);

  final Economy economy;

  @override
  Cached<Economy>? build() => Cached.live(economy);

  @override
  Future<void> refresh() async {}

  @override
  Future<void> ensureLoaded() async {}
}
