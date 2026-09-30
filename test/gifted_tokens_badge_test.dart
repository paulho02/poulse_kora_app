import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/features/feed/data/post.dart';
import 'package:peerkola/src/features/history/presentation/gifted_tokens_badge.dart';
import 'package:peerkola/src/features/history/presentation/history_post_detail_view.dart';

/// The author's gift counter in their post history: a number, with the sentence
/// in a tooltip that a tap opens on a phone — and a tap that stays the badge's
/// rather than opening the post the row belongs to.
void main() {
  Future<void> pump(WidgetTester tester, int? count, {VoidCallback? onRow}) =>
      tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: InkWell(
                onTap: onRow,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: GiftedTokensBadge(count: count),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('shows the count, and the sentence on tap', (tester) async {
    var rowTaps = 0;
    await pump(tester, 3, onRow: () => rowTaps++);

    expect(find.text('3'), findsOneWidget);
    expect(find.text('You were gifted 3 tokens for this post'), findsNothing);

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    expect(find.text('You were gifted 3 tokens for this post'), findsOneWidget);
    expect(
      rowTaps,
      0,
      reason: 'the tap explains the badge, not opens the post',
    );

    // Let the tooltip's show timer run out rather than outlive the test.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('one gift reads in the singular', (tester) async {
    await pump(tester, 1);
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(find.text('You were gifted 1 token for this post'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('nothing for no gifts, or for a post that is not yours', (
    tester,
  ) async {
    await pump(tester, 0);
    expect(find.byIcon(Icons.card_giftcard), findsNothing);
    await pump(tester, null);
    expect(find.byIcon(Icons.card_giftcard), findsNothing);
  });

  testWidgets('the opened own post carries the counter too', (tester) async {
    final post = Post.fromJson({
      'id': 1,
      'channel_id': 1,
      'channel_name': 'General',
      'blocks': [
        {'type': 'text', 'text': 'my post', 'media': null},
      ],
      'is_anonymous': false,
      'author': {'id': null, 'username': 'me', 'profile_picture_url': null},
      'subscription_kind': null,
      'created': '2026-09-30T12:00:00Z',
      'gifted_count': 2,
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showHistoryPostDetail(context, post: post),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('my post'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.card_giftcard));
    await tester.pumpAndSettle();
    expect(find.text('You were gifted 2 tokens for this post'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  test('the count is read off the post, and absent means not shown', () {
    Map<String, dynamic> json(Object? gifted) => {
      'id': 1,
      'channel_id': 1,
      'channel_name': 'General',
      'blocks': <Object>[],
      'is_anonymous': false,
      'author': {'id': null, 'username': null, 'profile_picture_url': null},
      'subscription_kind': null,
      'created': '2026-09-30T12:00:00Z',
      'gifted_count': ?gifted,
    };
    expect(Post.fromJson(json(4)).giftedCount, 4);
    // An older server, or anyone else's post: no field / null.
    expect(Post.fromJson(json(null)).giftedCount, isNull);
  });
}
