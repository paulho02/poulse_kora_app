import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../application/feed_providers.dart';

/// The Feed tab's nav icon, with the number of posts waiting over it.
///
/// The app had no way of saying "there is something to read" to anyone who was
/// not already looking at the feed: the queue is something the server *pushes*
/// into, the feed learns what is in it by polling `GET /posts/feed/status`, and
/// that answer reached nothing outside the feed screen. So a reader who checked
/// their stats and came back had to open the feed to find out whether opening
/// the feed was worth it.
///
/// This is deliberately *not* the count that used to sit in the feed's own app
/// bar and was removed (see `feed_screen.dart`). That one was a number nobody
/// acts on, because the posts it counted were directly underneath it — the list
/// is the count. Here the list is on another screen, which is a different job.
/// [selected] is the same reasoning applied consistently: while the feed is the
/// tab you are on, the badge is hidden.
///
/// It lives with the feed rather than in `routing/app_shell.dart` so that the
/// shell stays a list of five destinations, and so this is testable without
/// a `StatefulNavigationShell` to hang it from.
class FeedWaitingIcon extends ConsumerWidget {
  const FeedWaitingIcon({super.key, required this.selected});

  /// Whether the Feed tab is the one currently open.
  final bool selected;

  /// Past this, the count is shown as "9+". The queue's real cap
  /// (`FEED_QUEUE_MAX_SLOTS`) is a server setting this app does not know and
  /// should not have to — whatever it is raised to, three digits would not fit
  /// over a nav icon. Past a handful the exact number changes nothing anyone
  /// does: the instruction is "there is a stack waiting" either way.
  static const int maxShown = 9;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final waiting = ref.watch(feedQueueStatusProvider)?.postIds.length ?? 0;

    // `selectedIcon` handles the filled glyph; this is only ever the outline
    // one, so the selected case here is purely about suppressing the badge.
    const icon = Icon(Icons.forum_outlined);
    if (selected || waiting <= 0) return icon;

    return Badge(
      label: Text(waiting > maxShown ? '$maxShown+' : '$waiting'),
      // The accent, not `Badge`'s default error red. Posts waiting to be read
      // are the app working, not something wrong — red is what this app uses
      // for Drop and for deleting an account.
      backgroundColor: theme.colorScheme.primary,
      textColor: theme.colorScheme.onPrimary,
      // Spoken instead of the digits, which on their own announce as a bare
      // number with nothing saying what it counts.
      child: Semantics(label: l10n.feedWaitingBadge(waiting), child: icon),
    );
  }
}
