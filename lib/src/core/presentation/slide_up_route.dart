import 'package:flutter/material.dart';

/// A full-screen route that slides up from the bottom, the way a sheet does.
///
/// Used where a modal sheet's *motion* is right but its **size** is not: a post
/// with a photo or a video needs the whole screen for the media to be worth
/// looking at, and a bottom sheet is capped short of that (and, dragged taller,
/// still leaves the barrier and rounded corners eating the top of the picture).
/// This keeps the bottom-to-top gesture and gives the content everything.
///
/// Opaque, so the feed underneath stops painting once the transition finishes —
/// a translucent full-screen route keeps a whole second screen live behind it
/// for nothing.
Route<T> slideUpRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    fullscreenDialog: true,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // easeOutCubic in, easeInCubic out: the sheet-like "arrives quickly then
      // settles" feel, rather than the symmetric curve a default page gets.
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// The grab handle at the top of a [slideUpRoute] page: signals the route can be
/// dismissed downward, and does it.
///
/// The gesture lives on the handle rather than the whole page on purpose —
/// a page-wide vertical drag competes with the content's own scrolling, and
/// losing that race means a post that won't scroll.
class SlideDownDismissHandle extends StatefulWidget {
  const SlideDownDismissHandle({super.key, this.onDismiss});

  final VoidCallback? onDismiss;

  @override
  State<SlideDownDismissHandle> createState() => _SlideDownDismissHandleState();
}

class _SlideDownDismissHandleState extends State<SlideDownDismissHandle> {
  double _dragged = 0;

  void _dismiss() => (widget.onDismiss ?? () => Navigator.of(context).pop())();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _dragged = 0,
      onVerticalDragUpdate: (details) => _dragged += details.delta.dy,
      onVerticalDragEnd: (details) {
        // Either a deliberate pull or a quick flick counts — matching how a
        // real sheet closes, where a short fast swipe is the common gesture.
        if (_dragged > 80 || details.velocity.pixelsPerSecond.dy > 700) {
          _dismiss();
        }
      },
      child: SizedBox(
        height: 22,
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}
