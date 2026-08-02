import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../application/tip_providers.dart';

/// A small, dismissible explainer shown the first time a tab is opened in a
/// session — closing it with the "x" suppresses it for good (persisted via
/// `tipDismissalProvider`); only Settings' "Reset tutorial hints" brings it
/// back.
///
/// Wraps a screen's body: [child] is the screen's actual content, given the
/// remaining space below the card. Each tab keeps its own `State` alive
/// across tab switches (`StatefulShellRoute.indexedStack`), so "first opens
/// it" naturally means "first build this session" — tracked via
/// `tipSessionDismissalProvider` rather than local `State`, so Settings'
/// "Reset tutorial hints" can bring it back on an already-mounted tab.
class ViewTip extends ConsumerStatefulWidget {
  const ViewTip({
    super.key,
    required this.tipKey,
    required this.message,
    required this.child,
    this.icon = Icons.lightbulb_outline,
  });

  /// Unique per screen, e.g. `'tip.feed'`. Persisted verbatim as the
  /// forever-dismissal key.
  final String tipKey;
  final String message;
  final IconData icon;
  final Widget child;

  @override
  ConsumerState<ViewTip> createState() => _ViewTipState();
}

class _ViewTipState extends ConsumerState<ViewTip> {
  void _dismiss() {
    ref.read(tipSessionDismissalProvider.notifier).dismiss(widget.tipKey);
    ref.read(tipDismissalProvider.notifier).dismissForever(widget.tipKey);
  }

  @override
  Widget build(BuildContext context) {
    final dismissedForever = ref
        .watch(tipDismissalProvider)
        .contains(widget.tipKey);
    final sessionDismissed = ref
        .watch(tipSessionDismissalProvider)
        .contains(widget.tipKey);
    final visible = !sessionDismissed && !dismissedForever;

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: visible
              ? Padding(
                  // Bottom inset too, not just top/sides: without it the card
                  // sits flush against whatever the screen puts right below
                  // it (e.g. `EconomyStatusBar`'s own border), reading as one
                  // fused block instead of two distinct pieces.
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: _TipCard(
                    message: widget.message,
                    icon: widget.icon,
                    onClose: _dismiss,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.message,
    required this.icon,
    required this.onClose,
  });

  final String message;
  final IconData icon;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(message, style: theme.textTheme.bodyMedium),
              ),
            ),
            Semantics(
              label: l10n.tipDismiss,
              child: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
