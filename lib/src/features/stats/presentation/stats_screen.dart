import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/cache/cached.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/tips/presentation/view_tip.dart';
import '../../feed/data/post.dart';
import '../application/stats_providers.dart';
import '../data/post_stats.dart';
import '../data/user_stats.dart';
import 'stats_post_tile.dart';
import 'stats_skeleton.dart';
import 'trust_explainer.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statsProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsTitle)),
      body: ViewTip(
        tipKey: 'tip.stats',
        message: l10n.statsTipMessage,
        child: statsAsync.when(
          data: (cached) {
            final stats = cached.data;
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(statsProvider);
                ref.invalidate(ownPostViewsProvider);
                ref.invalidate(trendingPostsProvider);
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (cached.staleLabel != null) ...[
                    StaleDataNotice(label: cached.staleLabel!),
                    const SizedBox(height: 12),
                  ],
                  _TrustScoreCard(stats: stats),
                  const SizedBox(height: 12),
                  _ReviewScores(stats: stats),
                  const SizedBox(height: 12),
                  const _OwnPostViewsCard(),
                  const SizedBox(height: 12),
                  const _TrendingCard(),
                ],
              ),
            );
          },
          loading: () => const StatsSkeleton(),
          error: (error, _) => ErrorStateView(
            error: error,
            onRetry: () => ref.invalidate(statsProvider),
          ),
        ),
      ),
    );
  }
}

class _TrustScoreCard extends StatelessWidget {
  const _TrustScoreCard({required this.stats});

  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.statsTrustScore,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                // The same explanation the profile tile opens. Offered in both
                // places because this is a number with a consequence, and the
                // consequence is invisible: a reader whose forwards started
                // reaching fewer people has nothing else to connect that to.
                const TrustInfoButton(),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${stats.trustScore}',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(width: 6),
                Text(l10n.statsOutOf100, style: theme.textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: stats.trustScore / 100,
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The viewer's newest posts and how many people have viewed each. Loads
/// independently so a failure here doesn't blank out the personal stats above.
class _OwnPostViewsCard extends ConsumerWidget {
  const _OwnPostViewsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return _AsyncSectionCard<List<OwnPostViews>>(
      label: l10n.statsYourRecentPosts,
      value: ref.watch(ownPostViewsProvider),
      isEmpty: (entries) => entries.isEmpty,
      emptyMessage: l10n.statsNoOwnPosts,
      builder: (entries) => Column(
        children: [
          for (final entry in entries)
            StatsPostTile(
              post: entry.post,
              trailing: _ViewCount(count: entry.viewCount),
            ),
        ],
      ),
    );
  }
}

/// "12 views", with the sentence that says what a view is behind a tap — a
/// review is the only reading the server can count, so the word needs the
/// footnote.
class _ViewCount extends StatelessWidget {
  const _ViewCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.statsViewsExplained,
      triggerMode: TooltipTriggerMode.tap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.statsViews(count),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The top posts across Peerkola, with a way into the per-channel view. In
/// order only — the server sends no counts, so a reader is never handed a
/// score to vote along with.
class _TrendingCard extends ConsumerWidget {
  const _TrendingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return _AsyncSectionCard<List<Post>>(
      label: l10n.statsTrending,
      subtitle: l10n.statsTrendingSubtitle,
      action: TextButton(
        onPressed: () => context.push('/stats/trending'),
        child: Text(l10n.statsTrendingByChannel),
      ),
      value: ref.watch(trendingPostsProvider),
      isEmpty: (posts) => posts.isEmpty,
      emptyMessage: l10n.statsTrendingEmpty,
      builder: (posts) => Column(
        children: [for (final post in posts) StatsPostTile(post: post)],
      ),
    );
  }
}

/// A card on this screen whose content loads on its own: a small-caps label,
/// an optional subtitle and header action, then [builder]'s content, an empty
/// line, a spinner, or a quiet error line.
class _AsyncSectionCard<T> extends StatelessWidget {
  const _AsyncSectionCard({
    required this.label,
    required this.value,
    required this.isEmpty,
    required this.emptyMessage,
    required this.builder,
    this.subtitle,
    this.action,
  });

  final String label;
  final String? subtitle;
  final Widget? action;
  final AsyncValue<Cached<T>> value;
  final bool Function(T data) isEmpty;
  final String emptyMessage;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    Widget quietLine(String text) => SizedBox(
      height: 60,
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: theme.textTheme.labelSmall)),
                ?action,
              ],
            ),
            if (subtitle != null)
              Text(subtitle!, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            value.when(
              data: (cached) => isEmpty(cached.data)
                  ? quietLine(emptyMessage)
                  : builder(cached.data),
              loading: () => const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              ),
              // One card inside a working screen — a full error state would be
              // out of proportion, so it degrades to a quiet line.
              error: (error, _) => quietLine(messageFor(l10n, error)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which span the review scores show.
enum _ScoreSpan { total, week }

/// The viewer's own four review numbers, switchable between all time and the
/// last 7 days. Labelled "your reviews" because the bare grid read as if it
/// might be deployment-wide; each tile explains itself in a tap tooltip.
class _ReviewScores extends StatefulWidget {
  const _ReviewScores({required this.stats});

  final UserStats stats;

  @override
  State<_ReviewScores> createState() => _ReviewScoresState();
}

class _ReviewScoresState extends State<_ReviewScores> {
  var _span = _ScoreSpan.total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final totals = _span == _ScoreSpan.total
        ? widget.stats.allTime
        : widget.stats.thisWeek;
    final percent = NumberFormat.percentPattern(
      Localizations.localeOf(context).toString(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.statsYourReviews,
                  style: theme.textTheme.labelSmall,
                ),
              ),
              SegmentedButton<_ScoreSpan>(
                segments: [
                  ButtonSegment(
                    value: _ScoreSpan.total,
                    label: Text(l10n.statsSpanTotal),
                  ),
                  ButtonSegment(
                    value: _ScoreSpan.week,
                    label: Text(l10n.statsSpanWeek),
                  ),
                ],
                selected: {_span},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onSelectionChanged: (selection) =>
                    setState(() => _span = selection.first),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2,
          // Each tile carries the icon its verb already has elsewhere in the
          // app — the forward arrow off the feed card's Forward button, the
          // cross off Drop — so the grid can be read at a glance instead of by
          // parsing four identical number-over-label stacks. Forwarded and
          // dropped are also the only two that are *coloured*, because they
          // are the pair a reader compares; colouring all four would make none
          // of them stand out.
          children: [
            _MetricTile(
              icon: Icons.visibility_outlined,
              label: l10n.statsReviewed,
              tooltip: l10n.statsReviewedTooltip,
              value: '${totals.reviewedCount}',
            ),
            _MetricTile(
              icon: Icons.arrow_forward,
              label: l10n.statsForwarded,
              tooltip: l10n.statsForwardedTooltip,
              value: '${totals.forwardedCount}',
              tone: _MetricTone.forward,
            ),
            _MetricTile(
              icon: Icons.close,
              label: l10n.statsDropped,
              tooltip: l10n.statsDroppedTooltip,
              value: '${totals.droppedCount}',
              tone: _MetricTone.drop,
            ),
            _MetricTile(
              icon: Icons.percent,
              label: l10n.statsForwardRate,
              tooltip: l10n.statsForwardRateTooltip,
              value: percent.format(totals.forwardRate),
            ),
          ],
        ),
      ],
    );
  }
}

/// Which of the three colours a [_MetricTile] draws its icon in.
///
/// Only the two verbs get one. `neutral` is not "no opinion about this
/// number", it is "this number is not one of the pair".
enum _MetricTone { neutral, forward, drop }

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.value,
    this.tone = _MetricTone.neutral,
  });

  final IconData icon;
  final String label;

  /// What the number counts, in one sentence. Opened by a tap as well as a
  /// hover, so it works on a phone.
  final String tooltip;
  final String value;
  final _MetricTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (tone) {
      _MetricTone.forward => theme.colorScheme.primary,
      _MetricTone.drop => theme.colorScheme.error,
      _MetricTone.neutral => theme.colorScheme.onSurfaceVariant,
    };

    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.tap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // A tinted disc rather than a bare glyph, matching the empty
              // states (`core/presentation/empty_state.dart`) so the app has
              // one way of framing an icon rather than two.
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.12),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: theme.textTheme.headlineSmall,
                      maxLines: 1,
                    ),
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
