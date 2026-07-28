import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../application/tip_providers.dart';

/// A small, dismissible explainer shown the first time a tab is opened in a
/// session — close it with the "x", or check "Don't show again" to suppress
/// it for good (persisted via `tipDismissalProvider`).
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
  bool _dontShowAgain = false;

  void _dismiss() {
    ref.read(tipSessionDismissalProvider.notifier).dismiss(widget.tipKey);
    if (_dontShowAgain) {
      ref.read(tipDismissalProvider.notifier).dismissForever(widget.tipKey);
    }
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
                    dontShowAgain: _dontShowAgain,
                    onDontShowAgainChanged: (v) =>
                        setState(() => _dontShowAgain = v),
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
    required this.dontShowAgain,
    required this.onDontShowAgainChanged,
    required this.onClose,
  });

  final String message;
  final IconData icon;
  final bool dontShowAgain;
  final ValueChanged<bool> onDontShowAgainChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(message, style: theme.textTheme.bodyMedium),
                  ),
                  InkWell(
                    onTap: () => onDontShowAgainChanged(!dontShowAgain),
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 22,
                          width: 22,
                          child: Checkbox(
                            value: dontShowAgain,
                            onChanged: (v) =>
                                onDontShowAgainChanged(v ?? false),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "Don't show again",
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              label: 'Dismiss',
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
