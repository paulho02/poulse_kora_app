import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Caps the app's content width on a wide browser window.
///
/// Every screen here is laid out phone-first — full-bleed list rows, media
/// sized to the available width, `AppBar` actions at the far edges. Handed a
/// 1600px viewport those stretch into something unreadable: a post card three
/// words tall, a 4:5 image a metre wide. Rather than making each screen
/// responsive (a change across every feature), the whole app is rendered into
/// one centred column of at most [maxContentWidth] and the leftover is painted
/// as a gutter.
///
/// It wraps `MaterialApp.router`'s `builder`, i.e. *above* the Navigator, so it
/// covers routes that sit outside `AppShell` (login/register) and every dialog,
/// bottom sheet and snack bar the Navigator puts up — all of which are built
/// below this point in the tree.
///
/// Two things make it safe to drop in:
/// - **Web only** ([kIsWeb], a compile-time constant), so the Android build
///   tree-shakes it away and mobile layout is untouched. Removing that gate
///   would extend the same treatment to tablets and landscape phones.
/// - **[MediaQuery] is narrowed to match.** Without it the handful of widgets
///   that size themselves from `MediaQuery.sizeOf` (the economy header's label
///   cap, the channel picker sheet) would keep measuring against the window
///   and overflow the column. Only `size` is rewritten; insets and padding
///   still describe the real window, which is what the keyboard and safe-area
///   logic need.
class AppWidthLimit extends StatelessWidget {
  const AppWidthLimit({super.key, required this.child});

  /// Roughly a large phone. Wider reads as a desktop app the rest of the UI
  /// isn't designed for, and pushes a portrait (4:5) post image past the
  /// height of a typical laptop viewport.
  static const double maxContentWidth = 520;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;

    final scheme = Theme.of(context).colorScheme;
    // The gutter has to read as *behind* the app in both themes, and the
    // neutral ramp runs in opposite directions: in dark, "lowest" is the
    // darkest step (below `surface`); in light it is plain white, i.e. above.
    final gutter = scheme.brightness == Brightness.dark
        ? scheme.surfaceContainerLowest
        : scheme.surfaceContainerHigh;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= maxContentWidth) return child;

        final media = MediaQuery.of(context);
        return ColoredBox(
          color: gutter,
          child: Center(
            child: Container(
              width: maxContentWidth,
              height: constraints.maxHeight,
              // Foreground, not `decoration`: a normal border insets the
              // child, which would leave the column 2px narrower than the
              // width MediaQuery below is being told about.
              foregroundDecoration: BoxDecoration(
                border: Border.symmetric(
                  vertical: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: MediaQuery(
                data: media.copyWith(
                  size: Size(maxContentWidth, media.size.height),
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
