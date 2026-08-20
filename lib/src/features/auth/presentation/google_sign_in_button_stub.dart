import 'package:flutter/material.dart';

/// Non-web (Android) "continue with Google" button.
///
/// An ordinary app-drawn button, because these platforms let us start the flow
/// ourselves: [onPressed] calls `GoogleSignInService.signIn()`. The web build
/// swaps this whole file out for `google_sign_in_button_web.dart`, where Google's
/// SDK draws the button instead - see `google_sign_in_button.dart`.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;

  /// Null while a sign-in is already in flight, which also disables the button.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const _GoogleGlyph(),
      label: Text(label),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    );
  }
}

/// Google's four-colour "G", drawn rather than shipped as an asset so the button
/// needs no image binary and stays crisp at any size.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GoogleGlyphPainter()),
    );
  }
}

class _GoogleGlyphPainter extends CustomPainter {
  // Google's brand colours, fixed values by design: the "G" must look the same
  // in light and dark mode, so these deliberately do not come from the theme.
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    final stroke = s * 0.22;
    final radius = (s - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // Four arcs, in the order the brand mark reads clockwise from the bar.
    const quarter = 1.5707963; // pi / 2
    final arcs = <(Color, double)>[
      (_blue, -quarter * 0.35),
      (_green, quarter),
      (_yellow, quarter * 2),
      (_red, quarter * 3),
    ];
    for (final (color, start) in arcs) {
      canvas.drawArc(rect, start, quarter, false, paint..color = color);
    }

    // The horizontal bar of the "G".
    canvas.drawLine(
      Offset(center.dx, center.dy),
      Offset(s - stroke / 2, center.dy),
      Paint()
        ..color = _blue
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
