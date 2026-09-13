import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/l10n/generated/app_localizations.dart';
import 'package:poulse_kora_app/src/core/cache/cached.dart';
import 'package:poulse_kora_app/src/core/settings/app_settings.dart'
    show sharedPreferencesProvider;
import 'package:poulse_kora_app/src/features/channels/application/channels_providers.dart';
import 'package:poulse_kora_app/src/features/channels/data/channel.dart';
import 'package:poulse_kora_app/src/features/create_post/presentation/create_post_screen.dart';
import 'package:poulse_kora_app/src/features/create_post/presentation/token_spend_badge.dart';
import 'package:poulse_kora_app/src/features/economy/application/economy_providers.dart';
import 'package:poulse_kora_app/src/features/economy/data/economy.dart';
import 'package:poulse_kora_app/src/features/feed/application/feed_providers.dart';
import 'package:poulse_kora_app/src/features/feed/data/feed_repository.dart';
import 'package:poulse_kora_app/src/features/feed/data/post.dart';

/// Publishing costs tokens, and the balance simply being smaller afterwards
/// says nothing about why. The composer replays the subtraction where the
/// author is already looking — centred over the editor, the same place
/// `ForwardScoreBadge` lands over the card it belongs to.
void main() {
  Future<void> pumpComposer(
    WidgetTester tester, {
    int balance = 12,
    int balanceAfter = 8,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const CreatePostScreen()),
        GoRoute(
          path: '/feed',
          builder: (_, _) => const Scaffold(body: Text('feed')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          economyProvider.overrideWith(
            () => _FakeEconomy(Economy(tokenBalance: balance, postPrice: 4)),
          ),
          channelsNotifierProvider.overrideWith(_FakeChannels.new),
          feedRepositoryProvider.overrideWithValue(
            _FakeFeedRepository(balanceAfter),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Write a post and hit Relay, leaving the badge mid-play.
  Future<void> publish(WidgetTester tester) async {
    await tester.enterText(
      find.byType(TextField).first,
      'Das ist ein Test um zu sehen ob es funktioniert',
    );
    // Past the detector's debounce, so the language chip fills itself in and
    // the post has both halves of its route.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    // The chip reads "Select a channel" until one is picked; tapping it opens
    // the picker sheet, and the channel is chosen from there.
    await tester.tap(find.text('Select a channel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('General').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Relay'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('the badge plays over the editor, not in the app bar', (
    tester,
  ) async {
    await pumpComposer(tester);
    await publish(tester);

    expect(find.byType(TokenSpendBadge), findsOneWidget);

    // Centred on the body — the position `ForwardScoreBadge` uses, and the
    // whole point of it not being a flash on the corner pill, which is over
    // before an eye on the Relay button finds it.
    final screen = tester.getRect(find.byType(Scaffold).first);
    final badge = tester.getRect(find.byType(TokenSpendBadge));
    expect(
      badge.center.dx,
      closeTo(screen.center.dx, 1),
      reason: 'horizontally centred',
    );
    expect(
      badge.center.dy,
      lessThan(screen.bottom),
      reason: 'inside the body, not pinned to the top bar',
    );
    expect(badge.top, greaterThan(screen.top + 80));
  });

  testWidgets('shows the old balance and what it cost, then the new one', (
    tester,
  ) async {
    await pumpComposer(tester);
    await publish(tester);

    // The pairing is the effect: a number that drops instantly loses the
    // "before" half and reads as one blur.
    expect(find.text('12'), findsOneWidget);
    expect(find.text('−4'), findsOneWidget);
    // Without the label the pill is a bare count that reads as easily as the
    // post's price.
    expect(find.text('Your tokens:'), findsOneWidget);

    await tester.pump(kTokenSpendPlay);
    await tester.pumpAndSettle();
    // Gone, and the composer has moved on to the feed.
    expect(find.byType(TokenSpendBadge), findsNothing);
    expect(find.text('feed'), findsOneWidget);
  });

  testWidgets('a free post raises no badge at all', (tester) async {
    // The superuser case: nothing left the balance, and "−0" would be a claim
    // about a number that never moved.
    await pumpComposer(tester, balance: 12, balanceAfter: 12);
    await publish(tester);

    expect(find.byType(TokenSpendBadge), findsNothing);
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
      postPriceMin: 4,
      postPriceMax: 4,
    ),
  ]);

  @override
  Future<void> refreshPrices() async {}
}

class _FakeFeedRepository implements FeedRepository {
  _FakeFeedRepository(this.balanceAfter);

  final int balanceAfter;

  @override
  Future<CreatePostResult> createPost({
    required int channelId,
    required List<ComposerBlockInput> blocks,
    required String language,
    bool isAnonymous = false,
    List<PickedMedia> media = const [],
  }) async => CreatePostResult(
    post: Post.fromJson(const {
      'id': 1,
      'channel_id': 1,
      'channel_name': 'General',
      'language': 'de',
      'blocks': <dynamic>[],
      'is_anonymous': false,
      'author': {'id': null, 'username': null, 'profile_picture_url': null},
      'subscription_kind': null,
      'created': '2026-01-01T00:00:00Z',
    }),
    price: 4,
    tokenBalance: balanceAfter,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
