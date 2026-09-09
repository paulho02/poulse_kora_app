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

List<int> _ids(ProviderContainer c) =>
    c.read(feedNotifierProvider).value!.data.map((e) => e.postId).toList();

void main() {
  group('FeedNotifier top-up', () {
    test(
      'appends an arrival to the end instead of splicing it in at the top',
      () async {
        // The whole point of appending: the server orders the queue newest-first,
        // so inserting an arrival where the server puts it would shove the post
        // being read down the screen mid-sentence.
        final backend = _FakeBackend()..queue = [3, 2];
        final container = await _container(backend);
        await container.read(feedNotifierProvider.future);
        expect(_ids(container), [3, 2]);

        backend.queue = [4, 3, 2];
        await container.read(feedNotifierProvider.notifier).checkForArrivals();

        expect(_ids(container), [3, 2, 4]);
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
        expect(_ids(container), [3, 1]);

        backend.queue = [2, 3, 1]; // post 2 is channel 2 — filtered out
        final notifier = container.read(feedNotifierProvider.notifier);
        await notifier.checkForArrivals();
        final afterFirstLook = backend.feedRequests;
        await notifier.checkForArrivals();

        expect(_ids(container), [3, 1]);
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

      expect(_ids(container), [3, 2, 4]);
    });
  });
}
