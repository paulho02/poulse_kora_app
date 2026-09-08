import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/l10n/generated/app_localizations.dart';
import 'package:poulse_kora_app/src/core/cache/json_cache.dart';
import 'package:poulse_kora_app/src/features/economy/application/economy_providers.dart';
import 'package:poulse_kora_app/src/features/economy/data/economy_repository.dart';
import 'package:poulse_kora_app/src/features/feed/application/feed_providers.dart';
import 'package:poulse_kora_app/src/features/feed/data/feed_repository.dart';
import 'package:poulse_kora_app/src/features/feed/data/post.dart';
import 'package:poulse_kora_app/src/features/feed/presentation/forward_score_badge.dart';
import 'package:poulse_kora_app/src/features/feed/presentation/post_card.dart';

/// The forwarding score is the one number the server withholds until the reader
/// has committed to a verdict - a reader who can see the crowd is voting on the
/// crowd. These tests hold both halves of that: it is nowhere to be found
/// before the review, and it is on screen before the card is allowed to leave.
void main() {
  testWidgets('the score is absent until the verdict, then shown on the card', (
    tester,
  ) async {
    final backend = _FakeBackend(forwardedCount: 12);
    await _pumpCard(tester, backend);

    // Nothing on the card can show a score: the feed response carries none.
    expect(find.text('12'), findsNothing);

    await tester.tap(find.text('Forward'));
    await _pumpToReveal(tester);

    expect(find.text('12'), findsOneWidget);
    expect(
      backend.reviewedKinds,
      ['forward'],
      reason: 'the number came from the review, not from a second fetch',
    );
  });

  testWidgets('the card is not removed until the score has been seen', (
    tester,
  ) async {
    // The ordering is the feature: reveal, hold, *then* slide out. If removal
    // were committed on the server's answer, the badge would be landing on a
    // card already on its way off the list.
    final backend = _FakeBackend(forwardedCount: 3);
    final container = await _pumpCard(tester, backend);

    await tester.tap(find.text('Forward'));
    await _pumpToReveal(tester);

    expect(find.text('3'), findsOneWidget);
    expect(
      _feedIds(container),
      contains(1),
      reason: 'still in the feed while its score is on screen',
    );

    await _pumpPastExit(tester);

    expect(_feedIds(container), isNot(contains(1)));
    expect(find.text('a post'), findsNothing, reason: 'and the card is gone');
  });

  testWidgets("a drop reports the post's score too", (tester) async {
    // Worth its own case: the score describes the *post*, not a reward for
    // agreeing with the crowd, so dropping discloses it on the same terms.
    final backend = _FakeBackend(forwardedCount: 7);
    await _pumpCard(tester, backend);

    await tester.tap(find.text('Drop'));
    await _pumpToReveal(tester);

    expect(find.text('7'), findsOneWidget);
    expect(backend.reviewedKinds, ['drop']);
  });

  testWidgets('a refused review shows no score and keeps the card', (
    tester,
  ) async {
    // The server has the final say on whether a review counts at all (the post
    // may have left this queue), so there is no number to show and nothing to
    // animate.
    final backend = _FakeBackend(forwardedCount: 9, reviewStatus: 409);
    final container = await _pumpCard(tester, backend);

    await tester.tap(find.text('Forward'));
    await _pumpToReveal(tester);

    expect(find.text('9'), findsNothing);
    expect(_feedIds(container), contains(1));

    // Let the error snackbar time out rather than outlive the test.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  group('ForwardScoreBadge.heatFor', () {
    test('a first forward is cold', () {
      // At 1 the reader *is* the score - nothing to be impressed by yet.
      expect(ForwardScoreBadge.heatFor(0), 0);
      expect(ForwardScoreBadge.heatFor(1), 0);
    });

    test('rises with the count and tops out, log-scaled', () {
      expect(ForwardScoreBadge.heatFor(2), greaterThan(0));
      expect(ForwardScoreBadge.heatFor(50), 1);
      expect(ForwardScoreBadge.heatFor(5000), 1, reason: 'clamped');
      // Log, not linear: the midpoint sits near 7, not near 25. Counts compound
      // (every forward re-fans the post out to more readers), so a linear ramp
      // would leave every ordinary post looking identical.
      expect(ForwardScoreBadge.heatFor(7), closeTo(0.5, 0.03));
      expect(ForwardScoreBadge.heatFor(25), greaterThan(0.8));
    });
  });
}

List<int> _feedIds(ProviderContainer container) =>
    container.read(feedNotifierProvider).value!.data.map((p) => p.id).toList();

/// Runs time forward far enough for the review to resolve and the badge to pop
/// in, but not far enough for the hold to expire and the card to start leaving.
Future<void> _pumpToReveal(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(kForwardScorePopIn);
}

/// Runs out the hold and the exit animation after it.
///
/// Deliberately many small pumps rather than one long one plus `pumpAndSettle`:
/// the hold is a timer whose callback *starts* an animation, and a single pump
/// advances the clock past both without giving the frames in between — which
/// reads as "the card was never removed".
Future<void> _pumpPastExit(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Mounts a single card over a fake backend, and returns the container so a
/// test can ask what the feed still holds.
Future<ProviderContainer> _pumpCard(
  WidgetTester tester,
  _FakeBackend backend,
) async {
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

  // The card is built *from* the feed rather than handed a post directly, so
  // the post on screen and the post in the notifier's list are the same one and
  // its removal is observable. Awaiting the load outside `pump` would deadlock:
  // testWidgets runs on a fake clock that only advances when the tester pumps.
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final posts =
                  ref.watch(feedNotifierProvider).value?.data ?? const <Post>[];
              return posts.isEmpty
                  ? const SizedBox.shrink()
                  : PostCard(post: posts.first);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('a post'), findsOneWidget, reason: 'feed loaded');
  return container;
}

class _FakeBackend implements HttpClientAdapter {
  _FakeBackend({required this.forwardedCount, this.reviewStatus = 200});

  final int forwardedCount;
  final int reviewStatus;
  final List<String> reviewedKinds = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path == '/posts/feed') return _json([_post]);
    if (path == '/posts/feed/status') {
      return _json({
        'post_ids': [1],
        'capacity': 20,
      });
    }
    if (path == '/posts/1/review') {
      if (reviewStatus != 200) {
        return _json({
          'detail': {'error': 'not_in_queue'},
        }, status: reviewStatus);
      }
      final kind = (options.data as Map)['kind'] as String;
      reviewedKinds.add(kind);
      return _json({
        'post_id': 1,
        'kind': kind,
        'reviewed_count': 4,
        'review_gate': 3,
        'unlocked': true,
        'token_balance': 5,
        'post_forwarded_count': forwardedCount,
        'post_reviewed_count': forwardedCount + 1,
      });
    }
    throw StateError('unexpected request: $path');
  }

  static Map<String, dynamic> get _post => {
    'id': 1,
    'channel_id': 1,
    'channel_name': 'General',
    'blocks': [
      {'type': 'text', 'text': 'a post', 'media': null},
    ],
    'is_anonymous': false,
    'author': {'id': null, 'username': null, 'profile_picture_url': null},
    'subscription_kind': null,
    'created': DateTime.now().toUtc().toIso8601String(),
  };

  static ResponseBody _json(Object body, {int status = 200}) =>
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
