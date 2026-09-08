import 'package:flutter/material.dart';

/// A small "i" that explains one form field, as an [InputDecoration.suffixIcon].
///
/// Shared by the two screens that set a username so the affordance behaves the
/// same in both. [TooltipTriggerMode.tap] is the point of the widget: a default
/// Tooltip only opens on *long press* on touch devices, which nobody discovers —
/// and this exists to be discovered. Hover still works on web and desktop.
///
/// The padding is not decoration: it grows the tap target around a 16px icon,
/// which on its own would be far too small a thing to hit.
class FieldInfoIcon extends StatelessWidget {
  const FieldInfoIcon({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      // Longer than the 1.5s default: this is read, not glanced at.
      showDuration: const Duration(seconds: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          Icons.info_outline,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
