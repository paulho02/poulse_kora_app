import 'package:flutter/material.dart';

/// Placeholder shapes shown while a screen's first load is in flight.
///
/// The app used to answer every cold load with a centred
/// `CircularProgressIndicator`. A spinner says "something is happening" and
/// nothing else: it gives the reader no idea what is coming, it is the same
/// picture on all five tabs, and the layout it is replaced by arrives as one
/// abrupt jump. A skeleton says "a list of cards is coming, roughly this
/// shape", so the screen is legible before it has any content and the real
/// content lands into a layout that is already there.
///
/// Two rules for anything built here:
/// - **Shapes must match what replaces them.** A skeleton whose proportions
///   are wrong is worse than a spinner, because it promises a layout and then
///   reflows out of it.
/// - **Only for a cold load**, never for a refresh. Every screen in this app
///   can fall back to cached content (`core/cache/`), and replacing content
///   someone is reading with grey boxes would be a regression. These are
///   reached from `AsyncValue.loading` with no cached value, exactly where
///   the spinner used to be.
///
/// The sweep is driven by one controller per [Shimmer], not one per box: the
/// boxes are plain opaque rectangles and the ancestor paints the gradient over
/// all of them at once through a single `ShaderMask`. It also honours
/// `MediaQuery.disableAnimations`, which is the accessibility setting a
/// full-screen looping animation most needs to respect.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  /// The colour [SkeletonBox] paints itself, read off the nearest [Shimmer] so
  /// a box never has to guess at the theme.
  static Color baseColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Color.alphaBlend(
      scheme.onSurface.withValues(alpha: 0.07),
      scheme.surface,
    );
  }

  static Color _highlightColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Color.alphaBlend(
      scheme.onSurface.withValues(alpha: 0.15),
      scheme.surface,
    );
  }

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Started here rather than in `initState`, and stopped outright under
    // reduce-motion rather than merely left unpainted. A controller that is
    // repeating drives a frame callback whether or not anything reads it, so
    // building without the `ShaderMask` would have left a ticker running for a
    // sweep nobody is being shown — on the setting whose entire purpose is to
    // not run that animation. `didChangeDependencies` is also what makes this
    // follow the setting being changed while a skeleton is on screen.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduce-motion keeps the shapes and drops the sweep, which is the whole
    // point of the skeleton anyway.
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;

    final base = Shimmer.baseColor(context);
    final highlight = Shimmer._highlightColor(context);

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        // Sweeps a soft band from off the left edge to off the right one. The
        // -2..+2 travel is the gradient's own width (its stops span roughly a
        // third of the box) added to each side, so the band is fully clear of
        // the content at both ends of the cycle rather than snapping.
        final shift = _controller.value * 4 - 2;
        return ShaderMask(
          // srcATop paints the gradient only where the subtree is already
          // opaque — i.e. on the skeleton boxes, leaving their gaps alone.
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            colors: [base, highlight, base],
            stops: const [0.35, 0.5, 0.65],
            begin: Alignment(-1 + shift, -0.4),
            end: Alignment(1 + shift, 0.4),
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

/// One grey rectangle. Opaque on purpose — see [Shimmer]'s `srcATop`.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
    this.shape = BoxShape.rectangle,
  });

  /// A circle, for an avatar placeholder. [radius] is ignored.
  const SkeletonBox.circle({super.key, required double size})
    : width = size,
      height = size,
      radius = 0,
      shape = BoxShape.circle;

  final double? width;
  final double height;
  final double radius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Shimmer.baseColor(context),
        shape: shape,
        borderRadius: shape == BoxShape.circle
            ? null
            : BorderRadius.circular(radius),
      ),
    );
  }
}

/// A line of placeholder text, sized as a fraction of the available width so a
/// paragraph of them reads as prose rather than as a stack of equal bars.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.widthFactor = 1, this.height = 12});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: SkeletonBox(height: height, radius: height / 2),
    );
  }
}
