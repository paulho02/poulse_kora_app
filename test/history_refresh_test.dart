import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/l10n/generated/app_localizations.dart';
import 'package:poulse_kora_app/src/features/feed/data/post.dart';
import 'package:poulse_kora_app/src/features/history/application/history_providers.dart';
import 'package:poulse_kora_app/src/features/history/data/history_repository.dart';
import 'package:poulse_kora_app/src/features/history/data/reviewed_post.dart';
import 'package:poulse_kora_app/src/features/history/presentation/post_history_screen.dart';

/// The two ways to ask for fresh history, on the two list shapes that used to
/// swallow the gesture: an empty history (the message was rendered *instead of*
/// the refresh indicator) and one short enough to fit on screen (the list
/// refused the drag, so there was no overscroll to notice).
void main() {
  Future<_FakeHistoryRepository> pumpHistory(
    WidgetTester tester, {
    required int postCount,
  }) async {
    final repository = _FakeHistoryRepository(postCount: postCount);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [historyRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PostHistoryScreen(mode: HistoryMode.posted),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.fetchCount, 1, reason: 'first page on open');
    return repository;
  }

  testWidgets('the app bar button refetches an empty history', (tester) async {
    final repository = await pumpHistory(tester, postCount: 0);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(repository.fetchCount, 2);
  });

  testWidgets('an empty history can be pulled down', (tester) async {
    final repository = await pumpHistory(tester, postCount: 0);

    await tester.fling(
      find.text('You haven\'t posted anything yet.'),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(repository.fetchCount, 2);
  });

  testWidgets('a history shorter than the screen can be pulled down', (
    tester,
  ) async {
    final repository = await pumpHistory(tester, postCount: 1);

    await tester.fling(find.text('post 0'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(repository.fetchCount, 2);
  });

  testWidgets('the button also works with entries loaded', (tester) async {
    final repository = await pumpHistory(tester, postCount: 3);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(repository.fetchCount, 2);
  });
}

class _FakeHistoryRepository implements HistoryRepository {
  _FakeHistoryRepository({required this.postCount});

  final int postCount;

  /// Counts only first-page reads — which is what a refresh is.
  int fetchCount = 0;

  @override
  Future<List<Post>> fetchMyPosts({int skip = 0, int limit = 20}) async {
    if (skip == 0) fetchCount++;
    if (skip > 0) return const [];
    return List.generate(postCount, (i) => Post.fromJson(_postJson(i)));
  }

  @override
  Future<List<ReviewedPost>> fetchMyReviews({
    int skip = 0,
    int limit = 20,
  }) async => const [];
}

Map<String, dynamic> _postJson(int id) => {
  'id': id,
  'channel_id': 1,
  'channel_name': 'General',
  'blocks': [
    {'type': 'text', 'text': 'post $id', 'media': null},
  ],
  'is_anonymous': false,
  'author': {
    'id': 'ce1b6b1e-0000-4000-8000-000000000000',
    'username': 'ada',
    'profile_picture_url': null,
  },
  'forwarded_count': 0,
  'dropped_count': 0,
  'subscription_kind': null,
  'created': DateTime.now().toUtc().toIso8601String(),
};
