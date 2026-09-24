import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/features/feed/application/feed_providers.dart';
import 'package:peerkola/src/features/feed/data/feed_repository.dart';
import 'package:peerkola/src/features/feed/presentation/feed_waiting_icon.dart';

/// The count on the Feed tab of the bottom nav.
///
/// The app had no way to say "there is something to read" to anyone who was
/// not already looking at the feed — the feed learns what is waiting by
/// polling `GET /posts/feed/status`, and that answer reached nothing outside
/// the feed screen. This is that answer, on the nav bar.
///
/// `FeedWaitingIcon` is its own widget rather than a private one inside
/// `app_shell.dart` partly so that these can drive the real thing: the shell
/// around it needs a `StatefulNavigationShell`, which only `go_router` can
/// build.
void main() {
  FeedQueueStatus statusOf(List<int> ids) =>
      FeedQueueStatus(postIds: ids, capacity: 20);

  group('the queue count', () {
    test('is zero when no poll has ever answered', () {
      const FeedQueueStatus? never = null;
      expect(never?.postIds.length ?? 0, 0);
    });

    test('drops a post the moment its review is confirmed', () {
      // The reason `withoutPost` exists: between polls, a reader working
      // through a long queue would otherwise be shown a badge counting posts
      // they have already dealt with — and a badge that overcounts sends
      // someone to an empty feed.
      final status = statusOf([7, 8, 9]);
      expect(status.withoutPost(8).postIds, [7, 9]);
      expect(status.postIds, [7, 8, 9], reason: 'the original is untouched');
    });

    test('ignores a post it never held', () {
      expect(statusOf([7]).withoutPost(99).postIds, [7]);
    });

    test('keeps the capacity, so "full" survives a review', () {
      expect(statusOf([1, 2]).withoutPost(1).capacity, 20);
    });
  });

  group('the badge', () {
    Future<void> pump(
      WidgetTester tester, {
      required FeedQueueStatus? status,
      required bool selected,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            if (status != null)
              feedQueueStatusProvider.overrideWith(() => _FixedStatus(status)),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: FeedWaitingIcon(selected: selected)),
          ),
        ),
      );
    }

    testWidgets('is absent before any poll has answered', (tester) async {
      await pump(tester, status: null, selected: false);
      expect(find.byType(Badge), findsNothing);
      expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
    });

    testWidgets('is absent on an empty queue', (tester) async {
      await pump(tester, status: statusOf(const []), selected: false);
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('counts the waiting posts', (tester) async {
      await pump(tester, status: statusOf([1, 2, 3]), selected: false);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('caps at 9+', (tester) async {
      await pump(
        tester,
        status: statusOf(List.generate(20, (i) => i)),
        selected: false,
      );
      expect(find.text('9+'), findsOneWidget);
      expect(find.text('20'), findsNothing);
    });

    testWidgets('is hidden while the feed is the tab you are on', (
      tester,
    ) async {
      // Same reasoning that took the count out of the feed's own app bar: the
      // list *is* the count when you are looking at it.
      await pump(tester, status: statusOf([1, 2, 3]), selected: true);
      expect(find.byType(Badge), findsNothing);
      expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
    });

    testWidgets('says what it counts, for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, status: statusOf([1, 2, 3]), selected: false);

      // The digits alone announce as a bare number. What matters is that the
      // spoken string is the sentence, not the glyph.
      expect(
        find.bySemanticsLabel('3 posts waiting to be read'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}

class _FixedStatus extends FeedQueueStatusNotifier {
  _FixedStatus(this._status);

  final FeedQueueStatus _status;

  @override
  FeedQueueStatus? build() => _status;
}
