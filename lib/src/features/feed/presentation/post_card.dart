import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../application/feed_providers.dart';
import '../data/post.dart';

class PostCard extends ConsumerWidget {
  const PostCard({super.key, required this.post});

  final Post post;

  Future<void> _review(BuildContext context, WidgetRef ref, String kind) async {
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
    final color = AppColors.channelColor(post.channelName);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () => ref.read(expandedPostIdProvider.notifier).set(post.id),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _AuthorAvatar(post: post),
                  const SizedBox(width: 8),
                  Text(
                    post.isAnonymous ? 'Anonymous' : (post.author.username ?? 'Unknown'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontStyle: post.isAnonymous ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('·', style: theme.textTheme.labelSmall),
                  const SizedBox(width: 6),
                  Text(post.channelName, style: theme.textTheme.labelSmall?.copyWith(color: color)),
                  const Spacer(),
                  Text(
                    _timeAgo(post.created),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                post.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              if (post.hasImage) ...[
                const SizedBox(height: 10),
                Container(
                  height: 80,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text('IMAGE', style: theme.textTheme.labelSmall),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _review(context, ref, 'forward'),
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('Forward'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _review(context, ref, 'drop'),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Drop'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    if (post.isAnonymous) {
      return const CircleAvatar(
        radius: 12,
        child: Icon(Icons.person_outline, size: 14),
      );
    }
    final username = post.author.username ?? '?';
    final color = AppColors.avatarColor(username);
    return CircleAvatar(
      radius: 12,
      backgroundColor: color,
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}

String _timeAgo(DateTime created) {
  final diff = DateTime.now().toUtc().difference(created.toUtc());
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  return '${diff.inDays}d';
}
