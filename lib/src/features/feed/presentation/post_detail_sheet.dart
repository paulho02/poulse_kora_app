import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/feed_providers.dart';
import '../data/post.dart';

void showPostDetailSheet(BuildContext context, WidgetRef ref, Post post) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _PostDetailSheet(post: post),
  ).whenComplete(() => ref.read(expandedPostIdProvider.notifier).set(null));
}

class _PostDetailSheet extends ConsumerWidget {
  const _PostDetailSheet({required this.post});

  final Post post;

  Future<void> _review(BuildContext context, WidgetRef ref, String kind) async {
    Navigator.of(context).pop();
    try {
      await ref.read(feedNotifierProvider.notifier).reviewAndRemove(post.id, kind);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this post')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hoursLeft = post.timeRemaining.inHours;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('POST DETAIL', style: theme.textTheme.labelSmall),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  child: Icon(post.isAnonymous ? Icons.person_outline : Icons.person),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.isAnonymous ? 'Anonymous' : (post.author.username ?? 'Unknown'),
                      style: theme.textTheme.titleSmall,
                    ),
                    Text('${post.channelName} · $hoursLeft h left', style: theme.textTheme.labelSmall),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(post.text, style: theme.textTheme.bodyLarge),
            if (post.hasImage) ...[
              const SizedBox(height: 20),
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text('PHOTO', style: theme.textTheme.labelSmall),
              ),
            ],
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: post.deadlineProgress, minHeight: 4),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _review(context, ref, 'drop'),
                    icon: const Icon(Icons.close),
                    label: const Text('Drop'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _review(context, ref, 'forward'),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Forward'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
