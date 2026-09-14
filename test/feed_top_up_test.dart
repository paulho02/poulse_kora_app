import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/src/core/cache/json_cache.dart';
import 'package:poulse_kora_app/src/features/economy/application/economy_providers.dart';
import 'package:poulse_kora_app/src/features/economy/data/economy_repository.dart';
import 'package:poulse_kora_app/src/features/feed/application/feed_providers.dart';
import 'package:poulse_kora_app/src/features/feed/data/feed_repository.dart';

/// A stand-in backend whose review queue the test moves around underneath the
/// feed, the way the distribution worker does.
class _FakeBackend implements HttpClientAdapter {
  /// The queue as the server holds it: newest first, exactly how
  /// `GET /posts/feed` hands it back.
  List<int> queue = [];
  int capacity = 20;

  int feedRequests = 0;
  int statusRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path == '/posts/feed/status') {
      statusRequests++;
      return _json({'post_ids': queue, 'capacity': capacity});
    }
    if (path == '/posts/feed') {
      feedRequests++;
      final channelId = options.queryParameters['channel_id'] as int?;
      final visible = channelId == null
          ? queue
          : queue.where((id) => _channelOf(id) == channelId);
      return _json([for (final id in visible) _entry(id)]);
    }
    if (path == '/posts/economy') {
      return _json({
        'token_balance': 5,
        'post_price': 3,
        'post_price_expires_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    throw StateError('unexpected request: $path');
  }

  /// Odd ids belong to channel 1, even ids to channel 2 — enough to exercise
  /// the filter without a channel fixture.
  static int _channelOf(int postId) => postId.isOdd ? 1 : 2;

  /// Ids in [erased] resolve to a hole rather than a post - what a reader's
  /// queue looks like once the author has deleted their account.
  Set<int> erased = {};

  /// The `FeedEntry` envelope `GET /posts/feed` actually answers with.
  Map<String, dynamic> _entry(int id) => {
    'post_id': id,
    'post': erased.contains(id) ? null : _post(id),
  };

  static Map<String, dynamic> _post(int id) => {
    'id': id,
    'channel_id': _channelOf(id),
    'channel_name': 'c${_channelOf(id)}',
    'blocks': [
      {'type': 'text', 'text': 'post $id', 'media': null},
    ],
    'is_anonymous': false,
    'author': {'id': null, 'username': null, 'profile_picture_url': null},
    'subscription_kind': null,
    'created': DateTime.now().toUtc().toIso8601String(),
  };

  static ResponseBody _json(Object body) => ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      'content-type': ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

Future<ProviderContainer> _container(_FakeBackend backend) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final cache = JsonCache(prefs);
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
  dio.httpClientAdapter = backend;
  final container = ProviderContainer(
    overrides: [
      feedRepositoryProvider.overrideWithValue(FeedRepository(dio, cache)),
      economyRepositoryProvider.overrideWithValue(
        EconomyRepository(dio, cache),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The list on screen, oldest-at-top — the notifier's `data` is already in
/// this order (see `FeedNotifier._oldestFirst`), so this just names it.
List<int> _ids(ProviderContainer c) =>
    c.read(feedNotifierProvider).value!.data.map((e) => e.postId).toList();

void main() {
  group('FeedNotifier top-up', () {
    test(
      'appends an arrival to the end instead of splicing it in at the top',
      () async {
        // `_FakeBackend.queue` is given newest-placement-first, matching the
        // real `/posts/feed` route — so `[3, 2]` (3 placed after 2) is shown
        // as `[2, 3]`, the longer-waiting post on top. An arrival spliced in
        // where the server puts it (the top) would shove the post being read
        // down the screen mid-sentence.
        final backend = _FakeBackend()..queue = [3, 2];
        final container = await _container(backend);
        await container.read(feedNotifierProvider.future);
        expect(_ids(container), [2, 3]);

        backend.queue = [4, 3, 2];
        await container.read(feedNotifierProvider.notifier).checkForArrivals();

        expect(_ids(container), [2, 3, 4]);
      },
    );

    test(
      'two arrivals in the same batch still land oldest-then-newest',
      () async {
        // The server answers a batch of several new posts in its own
        // newest-first order too, so appending it as-is would put the newer
        // of the two arrivals above the older one within that batch — even
        // though the batch as a whole correctly sits below everything older.
        final backend = _FakeBackend()..queue = [2];
        final container = await _container(backend);
        await container.read(feedNotifierProvider.future);
        expect(_ids(container), [2]);

        backend.queue = [5, 4, 2]; // 5 placed after 4, both after 2
        await container.read(feedNotifierProvider.notifier).checkForArrivals();

        expect(_ids(container), [2, 4, 5]);
      },
    );

    test('a queue with nothing new in it costs no feed request', () async {
      final backend = _FakeBackend()..queue = [3, 2];
      final container = await _container(backend);
      await container.read(feedNotifierProvider.future);
      final afterLoad = backend.feedRequests;

      await container.read(feedNotifierProvider.notifier).checkForArrivals();
      await container.read(feedNotifierProvider.notifier).checkForArrivals();

      expect(backend.statusRequests, 2);
      expect(backend.feedRequests, afterLoad, reason: 'nothing arrived');
    });

    test(
      'an arrival hidden by the channel filter is asked about only once',
      () async {
        // The status lists the whole queue while a filtered feed holds part of
        // it, so without remembering what it has accounted for the client would
        // read the same hidden post as news on every single tick.
        final backend = _FakeBackend()..queue = [3, 1];
        final container = await _container(backend);
        container.read(selectedChannelFilterProvider.notifier).set(1);
        await container.read(feedNotifierProvider.future);
        expect(_ids(container), [1, 3]);

        backend.queue = [2, 3, 1]; // post 2 is channel 2 — filtered out
        final notifier = container.read(feedNotifierProvider.notifier);
        await notifier.checkForArrivals();
        final afterFirstLook = backend.feedRequests;
        await notifier.checkForArrivals();

        expect(_ids(container), [1, 3]);
        expect(backend.feedRequests, afterFirstLook);
      },
    );

    test('reports the queue status so the feed can say why it ends', () async {
      final backend = _FakeBackend()
        ..queue = [3, 2]
        ..capacity = 2;
      final container = await _container(backend);
      await container.read(feedNotifierProvider.future);

      await container.read(feedNotifierProvider.notifier).checkForArrivals();

      expect(container.read(feedQueueStatusProvider)!.isFull, isTrue);
    });

    test('a manual refresh leaves the posts where the reader had them', () async {
      // The server orders the queue newest-placement-first, but arrivals are
      // appended to the bottom — so taking the server's order wholesale on a
      // refresh resorted the whole list under the reader, jumping the post at
      // the bottom to the top. A review reliably produces such an arrival (it
      // frees the slot the worker then fills), which is how "I forwarded one
      // post, pulled to refresh, and everything moved" happened.
      final backend = _FakeBackend()..queue = [3, 2];
      final container = await _container(backend);
      await container.read(feedNotifierProvider.future);

      backend.queue = [4, 3, 2];
      await container.read(feedNotifierProvider.notifier).checkForArrivals();
      expect(_ids(container), [2, 3, 4]);

      await container.read(feedNotifierProvider.notifier).refresh();

      expect(
        _ids(container),
        [2, 3, 4],
        reason: 'not replaced wholesale with the raw fetch order',
      );
    });

    test('a manual refresh still syncs membership, only not order', () async {
      // Position is the reader's, membership is the server's: a post that has
      // left the queue goes, and one that has arrived lands at the end.
      final backend = _FakeBackend()..queue = [3, 2];
      final container = await _container(backend);
      await container.read(feedNotifierProvider.future);

      backend.queue = [5, 2];
      await container.read(feedNotifierProvider.notifier).refresh();

      expect(_ids(container), [2, 5]);
    });

    test('never removes a held post, only ever adds', () async {
      // Removal is the review's job alone. A top-up that pruned to whatever the
      // server currently holds would yank a card out mid-exit-animation, since
      // the review is accepted (and the post gone from the queue) a beat before
      // that animation ends.
      final backend = _FakeBackend()..queue = [3, 2];
      final container = await _container(backend);
      await container.read(feedNotifierProvider.future);

      backend.queue = [4];
      await container.read(feedNotifierProvider.notifier).checkForArrivals();

      expect(_ids(container), [2, 3, 4]);
    });
  });
}
