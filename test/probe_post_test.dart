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
import 'package:poulse_kora_app/src/features/feed/presentation/probe_marker.dart';
import 'package:poulse_kora_app/src/features/feed/presentation/probe_result_badge.dart';

/// A trust check is a post that measures the reader, and the two things that
/// makes non-negotiable are both covered here: the reader is *told* (the marker
/// is on the card, unprompted), and they are never shown a forwarding score for
/// it — a probe reaches one person, so any score it could show would be a true
/// number that means nothing and a tell that it was a check.
void main() {
  testWidgets('an ordinary post carries no check marker', (tester) async {
    await _pumpCard(tester, _FakeBackend(isProbe: false));

    expect(find.byType(ProbeMarker), findsNothing);
  });

  testWidgets('a check is marked on the card before it is answered', (
    tester,
  ) async {
    // Unprompted and up front: measuring someone without telling them is a
    // trick played on the reader, and a marker that only appeared afterwards
    // would be an explanation, not a disclosure.
    await _pumpCard(tester, _FakeBackend(isProbe: true));

    expect(find.byType(ProbeMarker), findsOneWidget);
  });

  testWidgets('answering a check reveals the verdict, not a score', (
    tester,
  ) async {
    final backend = _FakeBackend(isProbe: true, probeCorrect: true);
    await _pumpCard(tester, backend);

    await tester.tap(find.text('Forward'));
    await _pumpToReveal(tester);

    expect(find.byType(ProbeResultBadge), findsOneWidget);
    expect(
      find.byType(ForwardScoreBadge),
      findsNothing,
      reason: 'a probe has no score to disclose',
    );
    expect(backend.reviewedKinds, ['forward']);
  });

  testWidgets('getting one wrong is said plainly', (tester) async {
    // Kept visible on purpose. Without it, the only feedback a careless reader
    // ever gets is their forwards quietly reaching fewer people, with nothing
    // to connect that to anything they did.
    await _pumpCard(tester, _FakeBackend(isProbe: true, probeCorrect: false));

    await tester.tap(find.text('Drop'));
    await _pumpToReveal(tester);

    final badge = tester.widget<ProbeResultBadge>(
      find.byType(ProbeResultBadge),
    );
    expect(badge.correct, isFalse);
  });

  testWidgets('an unscorable check says only that it was one', (tester) async {
    // The server sends null when a probe's wording no longer matches any
    // variant. Claiming right or wrong there would be inventing a verdict.
    await _pumpCard(tester, _FakeBackend(isProbe: true, probeCorrect: null));

    await tester.tap(find.text('Forward'));
    await _pumpToReveal(tester);

    final badge = tester.widget<ProbeResultBadge>(
      find.byType(ProbeResultBadge),
    );
    expect(badge.correct, isNull);
  });

  testWidgets('an ordinary post still shows its score', (tester) async {
    // The guard on the branch above: `isProbe` must not have quietly replaced
    // the score reveal for every post.
    await _pumpCard(tester, _FakeBackend(isProbe: false, forwardedCount: 12));

    await tester.tap(find.text('Forward'));
    await _pumpToReveal(tester);

    expect(find.byType(ForwardScoreBadge), findsOneWidget);
    expect(find.byType(ProbeResultBadge), findsNothing);
    expect(find.text('12'), findsOneWidget);
  });

  group('Post.isProbe', () {
    test('defaults to false when the server does not say', () {
      // Older backends, and every response that predates the field. A post that
      // read as a check by accident would be marked as one on screen.
      final post = Post.fromJson(_FakeBackend.postJson(isProbe: null));
      expect(post.isProbe, isFalse);
    });

    test('is read straight off the response', () {
      expect(
        Post.fromJson(_FakeBackend.postJson(isProbe: true)).isProbe,
        isTrue,
      );
    });
  });

  group('PostReviewResult', () {
    test('a probe result carries no usable score', () {
      final result = PostReviewResult.fromJson(
        _FakeBackend.reviewJson(kind: 'forward', isProbe: true, correct: true),
      );

      expect(result.isProbe, isTrue);
      expect(result.probeCorrect, isTrue);
      expect(result.postForwardedCount, 0);
      expect(result.postReviewedCount, 0);
    });

    test('an ordinary result is unchanged', () {
      final result = PostReviewResult.fromJson(
        _FakeBackend.reviewJson(kind: 'drop', isProbe: false, forwarded: 4),
      );

      expect(result.isProbe, isFalse);
      expect(result.probeCorrect, isNull);
      expect(result.postForwardedCount, 4);
    });
  });
}

/// Runs time forward far enough for the review to resolve and the reveal to pop
/// in, but not far enough for the hold to expire and the card to leave. Same
/// beat as an ordinary post's score — deliberately, since a check that resolved
/// faster or slower would be a tell in itself.
Future<void> _pumpToReveal(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(kForwardScorePopIn);
}

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
              final posts = entries.whereType<FeedPost>().toList();
              return posts.isEmpty
                  ? const SizedBox.shrink()
                  : PostCard(post: posts.first.post);
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
  _FakeBackend({
    required this.isProbe,
    this.probeCorrect,
    this.forwardedCount = 0,
  });

  final bool isProbe;
  final bool? probeCorrect;
  final int forwardedCount;
  final List<String> reviewedKinds = [];

  static Map<String, dynamic> postJson({bool? isProbe}) => {
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
    // Omitted entirely when null, to stand in for a response that predates
    // the field.
    ?isProbe == null ? null : 'is_probe': isProbe,
  };

  static Map<String, dynamic> reviewJson({
    required String kind,
    required bool isProbe,
    bool? correct,
    int forwarded = 0,
  }) => {
    'post_id': 1,
    'kind': kind,
    'reviewed_count': 4,
    'review_gate': 3,
    'unlocked': true,
    'token_balance': 5,
    // Zeroed for a probe by the server, exactly as here: nobody else will ever
    // see the post, so there is no score to report.
    'post_forwarded_count': isProbe ? 0 : forwarded,
    'post_reviewed_count': isProbe ? 0 : forwarded + 1,
    'is_probe': isProbe,
    'probe_correct': correct,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path == '/posts/feed') {
      return _json([
        {'post_id': 1, 'post': postJson(isProbe: isProbe)},
      ]);
    }
    if (path == '/posts/feed/status') {
      return _json({
        'post_ids': [1],
        'capacity': 20,
      });
    }
    if (path == '/posts/1/review') {
      final kind = (options.data as Map)['kind'] as String;
      reviewedKinds.add(kind);
      return _json(
        reviewJson(
          kind: kind,
          isProbe: isProbe,
          correct: probeCorrect,
          forwarded: forwardedCount,
        ),
      );
    }
    throw StateError('unexpected request: $path');
  }

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
