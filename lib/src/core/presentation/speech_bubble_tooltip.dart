import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tap-to-show/tap-to-dismiss tooltip shaped like a solid-color speech bubble
/// with a triangular tail pointing at [child], instead of the default
/// rectangular [Tooltip]. Positions itself below [child] (or above it, if
/// there isn't room), and keeps the tail aligned with [child]'s center even
/// when the bubble itself has to shift sideways to stay on-screen.
class SpeechBubbleTooltip extends StatefulWidget {
  const SpeechBubbleTooltip({
    super.key,
    required this.message,
    required this.child,
    this.color,
    this.textColor,
  });

  final String message;
  final Widget child;

  /// Defaults to [ColorScheme.inverseSurface] — the Material 3 token meant
  /// for exactly this (tooltips/snackbars): high-contrast against the app's
  /// surfaces in both light and dark theme.
  final Color? color;
  final Color? textColor;

  @override
  State<SpeechBubbleTooltip> createState() => _SpeechBubbleTooltipState();
}

class _SpeechBubbleTooltipState extends State<SpeechBubbleTooltip> {
  OverlayEntry? _entry;
  Timer? _autoHide;

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _toggle() => _entry == null ? _show() : _hide();

  void _show() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final anchorTopLeft = box.localToGlobal(Offset.zero);
    final anchorSize = box.size;
    final theme = Theme.of(context);
    final bubbleColor = widget.color ?? theme.colorScheme.inverseSurface;
    final textColor = widget.textColor ?? theme.colorScheme.onInverseSurface;

    _entry = OverlayEntry(
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _hide,
        child: Stack(
          children: [
            _BubblePositioned(
              anchorTopLeft: anchorTopLeft,
              anchorSize: anchorSize,
              message: widget.message,
              color: bubbleColor,
              textColor: textColor,
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
    _autoHide?.cancel();
    _autoHide = Timer(const Duration(seconds: 6), _hide);
  }

  void _hide() {
    _autoHide?.cancel();
    _autoHide = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: _toggle, child: widget.child);
  }
}

class _BubblePositioned extends StatelessWidget {
  const _BubblePositioned({
    required this.anchorTopLeft,
    required this.anchorSize,
    required this.message,
    required this.color,
    required this.textColor,
  });

  final Offset anchorTopLeft;
  final Size anchorSize;
  final String message;
  final Color color;
  final Color textColor;

  static const double _maxWidth = 260;
  static const double _gap = 10;
  static const double _margin = 12;
  // Keep enough headroom that the flip decision doesn't need the bubble's
  // real (text-dependent) height up front.
  static const double _assumedBubbleHeight = 140;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final viewPadding = media.viewPadding;
    final anchorCenterX = anchorTopLeft.dx + anchorSize.width / 2;
    final anchorBottom = anchorTopLeft.dy + anchorSize.height;
    final anchorTop = anchorTopLeft.dy;

    final bubbleWidth = math.min(_maxWidth, screen.width - 2 * _margin);

    var left = anchorCenterX - bubbleWidth / 2;
    left = left.clamp(_margin, screen.width - _margin - bubbleWidth);
    final tailX = anchorCenterX - left;

    final spaceBelow = screen.height - viewPadding.bottom - anchorBottom;
    final showBelow =
        spaceBelow >= _assumedBubbleHeight ||
        spaceBelow >= anchorTop - viewPadding.top;

    return Positioned(
      left: left,
      top: showBelow ? anchorBottom + _gap : null,
      bottom: showBelow ? null : screen.height - anchorTop + _gap,
      width: bubbleWidth,
      child: _SpeechBubble(
        message: message,
        color: color,
        textColor: textColor,
        tailX: tailX,
        tailAtTop: showBelow,
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({
    required this.message,
    required this.color,
    required this.textColor,
    required this.tailX,
    required this.tailAtTop,
  });

  final String message;
  final Color color;
  final Color textColor;
  final double tailX;
  final bool tailAtTop;

  static const double _radius = 14;
  static const double _tailHeight = 8;
  static const double _tailBase = 16;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ClipPath(
        clipper: _BubbleClipper(
          tailX: tailX,
          tailAtTop: tailAtTop,
          radius: _radius,
          tailBase: _tailBase,
          tailHeight: _tailHeight,
        ),
        child: Container(
          color: color,
          padding: EdgeInsets.only(
            left: 14,
            right: 14,
            top: 10 + (tailAtTop ? _tailHeight : 0),
            bottom: 10 + (tailAtTop ? 0 : _tailHeight),
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: textColor),
          ),
        ),
      ),
    );
  }
}

/// Rounded-rect body with a triangular tail cut into one edge at [tailX],
/// clamped clear of the corners so it always renders as a clean point rather
/// than merging into the curve — the same safe-zone idea as the CSS
/// `min()`/`max()` clip-path trick this is styled after.
class _BubbleClipper extends CustomClipper<Path> {
  const _BubbleClipper({
    required this.tailX,
    required this.tailAtTop,
    required this.radius,
    required this.tailBase,
    required this.tailHeight,
  });

  final double tailX;
  final bool tailAtTop;
  final double radius;
  final double tailBase;
  final double tailHeight;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final r = radius;
    final bodyTop = tailAtTop ? tailHeight : 0.0;
    final bodyBottom = tailAtTop ? h : h - tailHeight;
    final tailEdgeY = tailAtTop ? bodyTop : bodyBottom;
    final apexY = tailAtTop ? 0.0 : h;
    final tailLeft = (tailX - tailBase / 2).clamp(r, w - r);
    final tailRight = (tailX + tailBase / 2).clamp(r, w - r);
    final apexX = tailX.clamp(0.0, w);

    final path = Path()..moveTo(r, bodyTop);
    if (tailAtTop) {
      path.lineTo(tailLeft, tailEdgeY);
      path.lineTo(apexX, apexY);
      path.lineTo(tailRight, tailEdgeY);
    }
    path.lineTo(w - r, bodyTop);
    path.arcToPoint(Offset(w, bodyTop + r), radius: Radius.circular(r));
    path.lineTo(w, bodyBottom - r);
    path.arcToPoint(Offset(w - r, bodyBottom), radius: Radius.circular(r));
    if (!tailAtTop) {
      path.lineTo(tailRight, tailEdgeY);
      path.lineTo(apexX, apexY);
      path.lineTo(tailLeft, tailEdgeY);
    }
    path.lineTo(r, bodyBottom);
    path.arcToPoint(Offset(0, bodyBottom - r), radius: Radius.circular(r));
    path.lineTo(0, bodyTop + r);
    path.arcToPoint(Offset(r, bodyTop), radius: Radius.circular(r));
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _BubbleClipper oldClipper) {
    return oldClipper.tailX != tailX ||
        oldClipper.tailAtTop != tailAtTop ||
        oldClipper.radius != radius ||
        oldClipper.tailBase != tailBase ||
        oldClipper.tailHeight != tailHeight;
  }
}
