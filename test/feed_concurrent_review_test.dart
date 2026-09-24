import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/core/cache/json_cache.dart';
import 'package:peerkola/src/core/settings/app_settings.dart';
import 'package:peerkola/src/features/channels/application/channels_providers.dart';
import 'package:peerkola/src/features/channels/data/channels_repository.dart';
import 'package:peerkola/src/features/economy/application/economy_providers.dart';
import 'package:peerkola/src/features/economy/data/economy_repository.dart';
import 'package:peerkola/src/features/feed/application/feed_providers.dart';
import 'package:peerkola/src/features/feed/data/feed_repository.dart';
import 'package:peerkola/src/features/feed/presentation/feed_screen.dart';
import 'package:peerkola/src/features/feed/presentation/post_card.dart';

/// Reviewing a second post while the first is still playing its score-and-slide
/// is ordinary use — the card takes ~1.1s to leave and a reader who already
/// knows what they think of the next post taps straight through that.
///
/// It used to leave the second post reviewed server-side but still on the list.
/// A sliver matches its children by index, so the first card's removal handed
/// row 1's widget to the element showing row 0; the keys differ, so every card
/// below was destroyed and rebuilt — taking with it the `State` that was
/// halfway through a review, the animation controllers it was awaiting, and the
/// `applyReviewResult` that was to follow. The rebuilt card came back with live
/// buttons on a post the server had already ruled on, good for one 409.
void main() {
  testWidgets('a second review started mid-animation still leaves the feed', (
    tester,
  ) async {
    final backend = _FakeBackend()..queue = [3, 2];
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = JsonCache(prefs);
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    dio.httpClientAdapter = backend;

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          feedRepositoryProvider.overrideWithValue(FeedRepository(dio, cache)),
          economyRepositoryProvider.overrideWithValue(
            EconomyRepository(dio, cache),
          ),
          channelsRepositoryProvider.overrideWithValue(
            ChannelsRepository(dio, cache),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const FeedScreen(),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(FeedScreen)),
    );
    // Let the feed and the channel list land.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(PostCard), findsNWidgets(2));

    // Forward the top card, then — a third of the way through its exit — the
    // one underneath it, which is the card that used to be rebuilt from
    // scratch. `warnIfMissed: false`: the first card is mid-slide and its own
    // button has moved out from under the tap point by the time this runs,
    // which is precisely the situation being tested.
    await tester.tap(find.byIcon(Icons.arrow_forward).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.arrow_forward).last, warnIfMissed: false);
    await tester.pump();

    // Long enough for both exits (~1.1s each, staggered by 400ms) to finish.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The server queue [3, 2] (3 newer) displays oldest-first, so post 2 is
    // the top card and 3 the one underneath.
    expect(backend.reviewed, [2, 3], reason: 'both reviews reached the server');
    expect(
      container.read(feedNotifierProvider).value!.data,
      isEmpty,
      reason: 'and both posts left the list',
    );
    expect(find.byType(PostCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// Just enough backend for two posts in one channel and the reviews of them.
class _FakeBackend implements HttpClientAdapter {
  List<int> queue = [];

  /// Post ids the client has actually submitted a verdict on, in order.
  final List<int> reviewed = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path == '/posts/feed') {
      return _json([
        for (final id in queue)
          {'post_id': id, 'post': _post(id)},
      ]);
    }
    if (path == '/posts/feed/status') {
      return _json({'post_ids': queue, 'capacity': 20});
    }
    if (path == '/channels') {
      return _json([
        {
          'id': 1,
          'name': 'c1',
          'color': '#10B981',
          'description': 'd',
          'is_subscribed': true,
          'post_price_min': 3,
          'post_price_max': 3,
        },
      ]);
    }
    if (path == '/posts/economy') {
      return _json({
        'token_balance': 5,
        'post_price': 3,
        'post_price_expires_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    final review = RegExp(r'^/posts/(\d+)/review$').firstMatch(path);
    if (review != null) {
      final id = int.parse(review.group(1)!);
      // The queue loses the post the moment the verdict is accepted, a beat
      // before the card that cast it has finished leaving — same as the real
      // backend, and what makes a top-up poll landing in between interesting.
      if (!queue.remove(id)) return _json({'detail': 'already reviewed'}, 409);
      reviewed.add(id);
      return _json({
        'post_id': id,
        'kind': 'forward',
        'reviewed_count': reviewed.length,
        'review_gate': 3,
        'unlocked': false,
        'token_balance': 5 + reviewed.length,
        'post_forwarded_count': 2,
        'post_reviewed_count': 4,
      });
    }
    throw StateError('unexpected request: $path');
  }

  static Map<String, dynamic> _post(int id) => {
    'id': id,
    'channel_id': 1,
    'channel_name': 'c1',
    'blocks': [
      {'type': 'text', 'text': 'post $id', 'media': null},
    ],
    'is_anonymous': false,
    'author': {'id': null, 'username': null, 'profile_picture_url': null},
    'subscription_kind': null,
    'created': DateTime.now().toUtc().toIso8601String(),
  };

  static ResponseBody _json(Object body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          'content-type': ['application/json'],
        },
      );

  @override
  void close({bool force = false}) {}
}
