import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/slide_up_route.dart';
import '../../channels/data/channel.dart';
import '../../feed/data/post.dart';
import '../../feed/presentation/post_detail_scaffold.dart';
import '../../profile/data/user_profile.dart';

/// Assemble the post being written into a [Post], so the preview can be drawn
/// by the reader's own widgets instead of by a second copy of the post layout.
///
/// The identifiers are placeholders ([Post.id] `-1`, and the channel's own id
/// when one is picked) and never leave the device: this object is built for one
/// screen and thrown away, and publishing still goes through `_submit`'s
/// `ComposerBlockInput` list. What it carries that the composer's editor cannot
/// show is everything *around* the article — who the reader sees as the author,
/// the channel and age line, the reading typography, and media running edge to
/// edge.
///
/// [author] is null while the profile hasn't loaded (or on an anonymous post,
/// where the reader is shown nothing about the author anyway).
Post buildPreviewPost({
  required List<PostBlock> blocks,
  required Channel? channel,
  required bool isAnonymous,
  required UserProfile? author,
}) {
  return Post(
    id: -1,
    channelId: channel?.id ?? -1,
    channelName: channel?.name ?? '',
    blocks: blocks,
    isAnonymous: isAnonymous,
    author: PostAuthor(
      id: author?.id,
      username: author?.username,
      profilePictureUrl: author?.profilePictureUrl,
    ),
    // Not knowable client-side: the supporter treatment comes off the snapshot
    // the backend takes when the post is created, and there is no
    // subscription field on the profile to anticipate it from. Previewing it as
    // an ordinary post is the safe direction — it under-promises.
    subscriptionKind: null,
    created: DateTime.now().toUtc(),
  );
}

/// Show the post as a reader will get it, over the composer.
///
/// Deliberately the *opened* post rather than its feed card: this is the view
/// that shows every block the author wrote, and it is where the decision to
/// forward or drop is actually made. It is also literally the reader's screen —
/// same [PostDetailScaffold], same [slideUpRoute] motion — so there is no second
/// layout to keep in step with the real one.
void showPostPreview(BuildContext context, Post post) {
  Navigator.of(
    context,
  ).push(slideUpRoute<void>(builder: (_) => _PostPreviewPage(post: post)));
}

class _PostPreviewPage extends StatelessWidget {
  const _PostPreviewPage({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hoursLeft = post.timeRemaining.inHours;
    // The same line the reader gets, minus the channel while none is picked —
    // previewing the writing shouldn't be gated on a decision made at publish
    // time, and a placeholder word in the channel's place would preview a
    // channel that doesn't exist.
    final meta = [
      if (post.channelName.isNotEmpty) post.channelName,
      l10n.postDetailPostedAgo(l10n.postJustNow),
      l10n.postDetailHoursLeft(hoursLeft),
    ].join(' · ');

    return PostDetailScaffold(
      post: post,
      metaLine: meta,
      progress: post.deadlineProgress,
      // The reader's footer, shown inert. It is part of what the post looks
      // like — it takes the bottom of the screen away from the article, and it
      // is the choice the writing has to survive — so leaving it out would
      // preview more room than the post actually gets. Disabled rather than
      // omitted, because nothing here has been published to review.
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _PreviewNotice(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: null,
                  icon: const Icon(Icons.close),
                  label: Text(l10n.postDrop),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(l10n.postForward),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Says what the screen is, right above the two buttons that would otherwise
/// look broken. Without it the only thing distinguishing a preview from a real
/// post is that nothing responds.
class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.visibility_outlined,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            l10n.postPreviewNotice,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
