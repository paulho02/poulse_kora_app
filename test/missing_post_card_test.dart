import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/l10n/generated/app_localizations.dart';
import 'package:poulse_kora_app/src/core/cache/json_cache.dart';
import 'package:poulse_kora_app/src/features/feed/application/feed_providers.dart';
import 'package:poulse_kora_app/src/features/feed/data/feed_repository.dart';
import 'package:poulse_kora_app/src/features/feed/data/post.dart';
import 'package:poulse_kora_app/src/features/feed/presentation/missing_post_card.dart';

/// The ghost card: a queue slot whose post has been erased by its author
/// deleting their account (see the backend's `app/core/account_deletion.py`).
///
/// The slot outlives the post — the backend's queue holds ids and nothing walks
/// every reader's queue at deletion time — so the feed has to be able to say
/// "this one is gone" and let the reader take the slot back.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('a hole in the queue renders as a card, not as nothing', (
    tester,
  ) async {
    final backend = _FakeBackend()
      ..queue = [2, 1]
      ..erased = {2};
    final container = await _pumpFeed(tester, backend);

    expect(find.text(l10n.feedMissingPostTitle), findsOneWidget);
    expect(find.text('post 1'), findsOneWidget);
    expect(
      container.read(feedNotifierProvider).value!.data.first,
      isA<MissingPost>(),
    );
  });

  testWidgets('it offers no way to forward — there is nothing to forward', (
    tester,
  ) async {
    final backend = _FakeBackend()
      ..queue = [2]
      ..erased = {2};
    await _pumpFeed(tester, backend);

    expect(find.text(l10n.postForward), findsNothing);
    expect(find.text(l10n.feedMissingPostDismiss), findsOneWidget);
  });

  testWidgets('dismissing clears the slot once the server has agreed', (
    tester,
  ) async {
    final backend = _FakeBackend()
      ..queue = [2, 1]
      ..erased = {2};
    final container = await _pumpFeed(tester, backend);

    await tester.tap(find.text(l10n.feedMissingPostDismiss));
    await tester.pumpAndSettle();

    expect(backend.dismissed, [2]);
    expect(
      container.read(feedNotifierProvider).value!.data.map((e) => e.postId),
      [1],
    );
    expect(find.text(l10n.feedMissingPostTitle), findsNothing);
  });

  testWidgets('a refusal leaves the card where it is and says so', (
    tester,
  ) async {
    // 409 `post_available` means this list is stale, not that the dismiss
    // failed — dropping the card would then hide a post still owed a verdict.
    final backend = _FakeBackend()
      ..queue = [2]
      ..erased = {2}
      ..dismissStatus = 409;
    final container = await _pumpFeed(tester, backend);

    await tester.tap(find.text(l10n.feedMissingPostDismiss));
    await tester.pumpAndSettle();

    expect(container.read(feedNotifierProvider).value!.data, hasLength(1));
    expect(find.text(l10n.errorPostAvailable), findsOneWidget);
  });
}

Future<ProviderContainer> _pumpFeed(
  WidgetTester tester,
  _FakeBackend backend,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
  dio.httpClientAdapter = backend;
  final container = ProviderContainer(
    overrides: [
      feedRepositoryProvider.overrideWithValue(
        FeedRepository(dio, JsonCache(prefs)),
      ),
    ],
  );
  addTearDown(container.dispose);

  // Built from the notifier rather than handed a fixed entry, so the removal a
  // dismiss performs is observable on screen as well as in the list.
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final entries =
                  ref.watch(feedNotifierProvider).value?.data ??
                  const <FeedEntry>[];
              return ListView(
                children: [
                  for (final entry in entries)
                    switch (entry) {
                      FeedPost(:final post) => Text(post.previewText),
                      MissingPost(:final postId) => MissingPostCard(
                        postId: postId,
                      ),
                    },
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

class _FakeBackend implements HttpClientAdapter {
  List<int> queue = [];
  Set<int> erased = {};
  int dismissStatus = 204;
  final List<int> dismissed = [];

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
          {'post_id': id, 'post': erased.contains(id) ? null : _post(id)},
      ]);
    }
    if (path == '/posts/feed/status') {
      return _json({'post_ids': queue, 'capacity': 20});
    }
    if (path.startsWith('/posts/feed/')) {
      final id = int.parse(path.split('/').last);
      if (dismissStatus != 204) {
        return _json({
          'detail': {'error': 'post_available'},
        }, status: dismissStatus);
      }
      dismissed.add(id);
      queue = [...queue]..remove(id);
      return _json(null, status: 204);
    }
    throw StateError('unexpected request: $path');
  }

  static Map<String, dynamic> _post(int id) => {
    'id': id,
    'channel_id': 1,
    'channel_name': 'General',
    'blocks': [
      {'type': 'text', 'text': 'post $id', 'media': null},
    ],
    'is_anonymous': false,
    'author': {'id': null, 'username': null, 'profile_picture_url': null},
    'subscription_kind': null,
    'created': DateTime.now().toUtc().toIso8601String(),
  };

  static ResponseBody _json(Object? body, {int status = 200}) =>
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
