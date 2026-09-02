import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../application/tip_providers.dart';

/// The modal sibling of `ViewTip`: an explainer for a choice the user just
/// made, rather than for a screen they just opened.
///
/// Shares `ViewTip`'s two dismissal lifetimes, and therefore its keyspace and
/// Settings' "Reset tutorial hints" (`resetAllTips`) — a tip is a tip
/// regardless of how it's drawn. The split differs from `ViewTip` though:
/// closing this one only silences it for the session, and it takes the
/// checkbox to silence it for good. A modal interrupts, so it can afford to
/// ask; an inline card can't, which is why closing *that* one is final.
///
/// Returns as soon as the dialog is gone. Does nothing (and awaits nothing) if
/// the tip is already dismissed either way, so callers can fire it
/// unconditionally at the moment the choice is made.
Future<void> showTipDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String tipKey,
  required String title,
  required String message,
  IconData icon = Icons.lightbulb_outline,
}) async {
  if (ref.read(tipDismissalProvider).contains(tipKey) ||
      ref.read(tipSessionDismissalProvider).contains(tipKey)) {
    return;
  }

  // Resolved before the await: the caller's `ref` may outlive this dialog by
  // no more than the widget that owns it, and the notifiers are root-scoped
  // anyway.
  final session = ref.read(tipSessionDismissalProvider.notifier);
  final forever = ref.read(tipDismissalProvider.notifier);

  final dontShowAgain =
      await showDialog<bool>(
        context: context,
        builder: (context) =>
            _TipDialog(title: title, message: message, icon: icon),
      ) ??
      false;

  session.dismiss(tipKey);
  if (dontShowAgain) await forever.dismissForever(tipKey);
}

class _TipDialog extends StatefulWidget {
  const _TipDialog({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  State<_TipDialog> createState() => _TipDialogState();
}

class _TipDialogState extends State<_TipDialog> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      icon: Icon(widget.icon, color: theme.colorScheme.primary),
      title: Text(widget.title),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _dontShowAgain = !_dontShowAgain),
            borderRadius: BorderRadius.circular(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Checkbox(
                    value: _dontShowAgain,
                    onChanged: (v) =>
                        setState(() => _dontShowAgain = v ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.infoBannerDontShowAgain,
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          // The checkbox rides out on the same pop, so a tap outside (which
          // pops with null) can never persist a dismissal the user only
          // half-made.
          onPressed: () => Navigator.of(context).pop(_dontShowAgain),
          child: Text(l10n.commonGotIt),
        ),
      ],
    );
  }
}
