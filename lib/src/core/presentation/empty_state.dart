import 'package:flutter/material.dart';

/// The one "there is nothing here" state, shaped to match [ErrorStateView] in
/// `error_state_view.dart` so an empty screen and a failed one read as two
/// members of one family rather than as two accidents.
///
/// It lived as a private widget inside `feed_screen.dart`, which is why the
/// channel list answered an empty search with a bare centred `Text` and the
/// history screens with nothing at all — the good version was not reachable.
/// Three things it insists on, each of which the bare-text version dropped:
/// an **icon**, so the state is recognisable before it is read; a **subtitle**
/// saying why it is empty rather than only that it is; and an **action**
/// wherever there is one, because most empty states in this app are one tap
/// from not being empty (join a channel, clear a filter).
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The icon sits in a tinted disc rather than floating on the
            // background. A lone 48dp outline glyph in `outline` grey reads as
            // a rendering failure as easily as a designed state; a container
            // gives it a deliberate silhouette at no extra colour cost.
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              child: Icon(
                icon,
                size: 34,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// [EmptyStateView] in a scroll view, so an enclosing `RefreshIndicator` still
/// picks up the pull gesture when there is no list left to scroll.
///
/// Every empty state under a pull-to-refresh needs this: the gesture is the
/// reflex for "surely there is something by now", and it is exactly the state
/// with nothing to scroll that makes people try it.
class ScrollableEmptyState extends StatelessWidget {
  const ScrollableEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: EmptyStateView(
            icon: icon,
            title: title,
            subtitle: subtitle,
            actionLabel: actionLabel,
            onAction: onAction,
          ),
        ),
      ),
    );
  }
}
