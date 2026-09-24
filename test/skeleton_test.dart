import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/core/presentation/empty_state.dart';
import 'package:peerkola/src/core/presentation/skeleton.dart';
import 'package:peerkola/src/core/theme/app_theme.dart';
import 'package:peerkola/src/features/channels/presentation/channels_skeleton.dart';
import 'package:peerkola/src/features/feed/presentation/feed_skeleton.dart';
import 'package:peerkola/src/features/history/presentation/history_skeleton.dart';
import 'package:peerkola/src/features/profile/presentation/profile_skeleton.dart';
import 'package:peerkola/src/features/stats/presentation/stats_skeleton.dart';

/// The placeholder shapes that replaced the centred spinner on every cold
/// load, plus the shared empty state they eventually resolve into.
///
/// Worth pinning for two reasons. A skeleton is only ever seen for a second
/// and only on a *cold* load, so a layout assertion inside one would reach
/// almost nobody before a release — and the `Shimmer` sweep repeats forever,
/// which is the one animation shape that hangs `pumpAndSettle` if it is ever
/// wired up without an escape.
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  group('skeletons render', () {
    final cases = <String, Widget>{
      'feed': const FeedSkeleton(),
      'channels': const ChannelsSkeleton(),
      'stats': const StatsSkeleton(),
      'profile': const ProfileSkeleton(),
      'history': const HistorySkeleton(),
    };

    for (final entry in cases.entries) {
      testWidgets('${entry.key} lays out in both themes', (tester) async {
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(host(entry.value, brightness: brightness));
          // One frame past the start, so the shimmer's first driven rebuild is
          // included rather than only its initial state.
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          expect(find.byType(SkeletonBox), findsWidgets);
        }
      });
    }
  });

  testWidgets('the shimmer sweeps forever and so is never settled', (
    tester,
  ) async {
    await tester.pumpWidget(host(const FeedSkeleton()));
    await tester.pump(const Duration(milliseconds: 700));
    // A repeating controller never completes, so `pumpAndSettle` would spin
    // until it timed out. Anything that awaits a settle while one of these is
    // on screen has to reach a state where it is gone first — which is what a
    // real screen does by resolving its `AsyncValue`.
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('reduce-motion keeps the shapes and drops the sweep', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: host(const FeedSkeleton()),
      ),
    );
    await tester.pump();

    expect(find.byType(SkeletonBox), findsWidgets);
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('an empty state with no action shows no button', (tester) async {
    await tester.pumpWidget(
      host(
        const EmptyStateView(
          icon: Icons.inbox_outlined,
          title: 'Nothing here',
          subtitle: 'Come back later.',
        ),
      ),
    );

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Come back later.'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('an empty state with an action can be tapped', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      host(
        EmptyStateView(
          icon: Icons.inbox_outlined,
          title: 'Nothing here',
          subtitle: 'But there could be.',
          actionLabel: 'Fix it',
          onAction: () => tapped++,
        ),
      ),
    );

    await tester.tap(find.text('Fix it'));
    expect(tapped, 1);
  });

  testWidgets('a scrollable empty state can be pulled', (tester) async {
    // The reason this variant exists: an empty screen is exactly where someone
    // pulls to refresh, and a bare `Center` gives the gesture nothing to grab.
    var refreshed = 0;
    await tester.pumpWidget(
      host(
        RefreshIndicator(
          onRefresh: () async => refreshed++,
          child: const ScrollableEmptyState(
            icon: Icons.inbox_outlined,
            title: 'Nothing here',
            subtitle: 'Pull to check again.',
          ),
        ),
      ),
    );

    await tester.fling(find.text('Nothing here'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(refreshed, 1);
  });
}
