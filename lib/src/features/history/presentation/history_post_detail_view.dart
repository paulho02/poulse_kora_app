import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/slide_up_route.dart';
import '../../feed/data/post.dart';
import '../../feed/presentation/post_detail_scaffold.dart';
import 'gifted_tokens_badge.dart';

/// Read-only counterpart of the feed's post view (see
/// `feed/presentation/post_detail_view.dart`) for posts shown in a history
/// list: no drop/forward footer and no review-deadline bar, since a history
/// entry is already published/already reviewed rather than sitting in the
/// active queue.
void showHistoryPostDetail(
  BuildContext context, {
  required Post post,
  String? reviewKindLabel,
  DateTime? reviewedAt,
}) {
  Navigator.of(context).push(
    slideUpRoute<void>(
      builder: (_) => _HistoryPostDetailPage(
        post: post,
        reviewKindLabel: reviewKindLabel,
        reviewedAt: reviewedAt,
      ),
    ),
  );
}

String _relativeAgo(DateTime dt) {
  final diff = DateTime.now().toUtc().difference(dt.toUtc());
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  return '${diff.inDays}d';
}

class _HistoryPostDetailPage extends StatelessWidget {
  const _HistoryPostDetailPage({
    required this.post,
    this.reviewKindLabel,
    this.reviewedAt,
  });

  final Post post;
  final String? reviewKindLabel;
  final DateTime? reviewedAt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final postedAgoRaw = _relativeAgo(post.created);
    final postedAgo = postedAgoRaw == 'now'
        ? l10n.postJustNow
        : l10n.postTimeAgoSuffix(postedAgoRaw);

    final meta = StringBuffer(
      '${post.channelName} · ${l10n.postDetailPostedAgo(postedAgo)}',
    );
    final kind = reviewKindLabel;
    final at = reviewedAt;
    if (kind != null && at != null) {
      final ago = _relativeAgo(at);
      meta.write(
        ' · $kind · '
        '${l10n.historyDetailReviewedAgo(ago == 'now' ? l10n.postJustNow : l10n.postTimeAgoSuffix(ago))}',
      );
    }

    return PostDetailScaffold(
      post: post,
      metaLine: meta.toString(),
      // Renders nothing unless this is the viewer's own post with gifts: the
      // server sends the count to the author only.
      metaTrailing: GiftedTokensBadge(count: post.giftedCount),
    );
  }
}
