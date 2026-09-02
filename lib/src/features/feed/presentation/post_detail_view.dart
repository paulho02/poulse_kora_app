import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/presentation/slide_up_route.dart';
import '../application/feed_providers.dart';
import '../data/post.dart';
import 'post_detail_scaffold.dart';

/// Opens a post for review, full screen.
///
/// Was a `showModalBottomSheet` + `DraggableScrollableSheet`: the motion was
/// right but the size never was, since a sheet tops out short of the screen and
/// keeps a barrier and rounded corners over the top of whatever photo or video
/// the post is actually about. [slideUpRoute] keeps the slide-from-bottom and
/// gives the post the whole screen.
void showPostDetail(BuildContext context, WidgetRef ref, Post post) {
  Navigator.of(context)
      .push(slideUpRoute<void>(builder: (_) => _PostDetailPage(post: post)))
      .whenComplete(() => ref.read(expandedPostIdProvider.notifier).set(null));
}

class _PostDetailPage extends ConsumerWidget {
  const _PostDetailPage({required this.post});

  final Post post;

  Future<void> _review(BuildContext context, WidgetRef ref, String kind) async {
    // Grab the messenger before popping: afterwards this page's context is
    // defunct, and a `context.mounted` check would just swallow the error.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    Navigator.of(context).pop();
    try {
      await ref
          .read(feedNotifierProvider.notifier)
          .reviewAndRemove(post.id, kind);
    } catch (error) {
      showErrorSnackBarOn(messenger, l10n, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hoursLeft = post.timeRemaining.inHours;
    final postedAgo = post.timeAgo == 'now'
        ? l10n.postJustNow
        : l10n.postTimeAgoSuffix(post.timeAgo);

    return PostDetailScaffold(
      post: post,
      metaLine:
          '${post.channelName} · ${l10n.postDetailPostedAgo(postedAgo)} · '
          '${l10n.postDetailHoursLeft(hoursLeft)}',
      progress: post.deadlineProgress,
      footer: Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => _review(context, ref, 'drop'),
              icon: const Icon(Icons.close),
              label: Text(l10n.postDrop),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _review(context, ref, 'forward'),
              icon: const Icon(Icons.arrow_forward),
              label: Text(l10n.postForward),
            ),
          ),
        ],
      ),
    );
  }
}
