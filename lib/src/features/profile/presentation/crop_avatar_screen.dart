import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';

/// Side length of the image this screen produces. An avatar is drawn at 72px at
/// its largest, so 512 is generous even on a high-DPI screen, and a PNG that
/// size lands far inside the backend's 2 MB limit.
const int _outputSize = 512;

/// Which rectangle of the *source image*, in pixels, is currently framed by the
/// square preview.
///
/// Pure geometry, kept out of the widget so it can be checked directly — this is
/// the part of cropping that can silently be wrong, and being off by a factor
/// would produce a plausible-looking picture of the wrong region.
///
/// Two coordinate hops: the transform maps the InteractiveViewer's child to the
/// viewport (so it is inverted here to ask what the viewport is showing), and
/// the child holds the image under `BoxFit.cover` (so that fit is undone to get
/// back to pixels). The result is clamped to the image, since a transform is
/// only bounded to the child, not to the image's letterboxed area within it.
@visibleForTesting
Rect cropSourceRect({
  required Matrix4 transform,
  required double viewportSize,
  required double imageWidth,
  required double imageHeight,
}) {
  final coverScale = math.max(
    viewportSize / imageWidth,
    viewportSize / imageHeight,
  );
  final dx = (viewportSize - imageWidth * coverScale) / 2;
  final dy = (viewportSize - imageHeight * coverScale) / 2;

  final inverse = Matrix4.inverted(transform);
  final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
  final bottomRight = MatrixUtils.transformPoint(
    inverse,
    Offset(viewportSize, viewportSize),
  );

  return Rect.fromLTRB(
    ((topLeft.dx - dx) / coverScale).clamp(0.0, imageWidth),
    ((topLeft.dy - dy) / coverScale).clamp(0.0, imageHeight),
    ((bottomRight.dx - dx) / coverScale).clamp(0.0, imageWidth),
    ((bottomRight.dy - dy) / coverScale).clamp(0.0, imageHeight),
  );
}

/// Square crop with pan and zoom, shown after picking an image.
///
/// Returns PNG bytes, or null if the user backs out.
///
/// Producing the bytes here rather than uploading what the picker returned is
/// what makes the result predictable: `image_picker` re-encodes differently per
/// platform (its web resizer goes through a canvas and emits PNG; Android emits
/// JPEG), so without this step the format — and the content type we would have
/// to declare for it — depended on where the app was running.
class CropAvatarScreen extends StatefulWidget {
  const CropAvatarScreen({super.key, required this.image});

  final ui.Image image;

  @override
  State<CropAvatarScreen> createState() => _CropAvatarScreenState();
}

class _CropAvatarScreenState extends State<CropAvatarScreen> {
  final _controller = TransformationController();
  var _saving = false;

  /// Side of the square preview, recorded by the LayoutBuilder below. The crop
  /// maths has to run against the frame the user actually saw, so this is read
  /// from layout rather than re-derived from MediaQuery — the preview is sized
  /// by what the controls leave over, which MediaQuery alone doesn't know.
  double? _viewportSize;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm(double viewportSize) async {
    setState(() => _saving = true);
    final bytes = await _render(viewportSize);
    if (!mounted) return;
    Navigator.of(context).pop(bytes);
  }

  /// Map the visible part of the viewport back to source pixels, then draw just
  /// that region into a fixed-size square.
  Future<Uint8List?> _render(double viewportSize) async {
    final image = widget.image;
    final src = cropSourceRect(
      transform: _controller.value,
      viewportSize: viewportSize,
      imageWidth: image.width.toDouble(),
      imageHeight: image.height.toDouble(),
    );
    // A degenerate rect would make `drawImageRect` throw rather than produce a
    // blank picture; nothing sane should reach it, but the crop is user-driven.
    if (src.width <= 0 || src.height <= 0) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(0, 0, _outputSize.toDouble(), _outputSize.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(_outputSize, _outputSize);
    picture.dispose();
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    return data?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.cropAvatarTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = math.min(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    _viewportSize = size;
                    return SizedBox(
                      width: size,
                      height: size,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          InteractiveViewer(
                            transformationController: _controller,
                            // Zero margin keeps the image covering the frame at
                            // all times, so there is no way to crop in empty
                            // space and end up with transparent edges.
                            boundaryMargin: EdgeInsets.zero,
                            minScale: 1,
                            maxScale: 5,
                            child: SizedBox(
                              width: size,
                              height: size,
                              child: RawImage(
                                image: widget.image,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          // Guide only — the saved image is the full square. It
                          // shows what will actually survive the circular crop
                          // every avatar in the app applies when displaying it.
                          const IgnorePointer(
                            child: _CircleGuide(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    l10n.cropAvatarHint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: Text(l10n.commonCancel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _onSave,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.commonSave),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSave() {
    final size = _viewportSize;
    // Only null if the preview never laid out, which cannot happen while the
    // button it sits beside is on screen.
    if (size == null || size <= 0) return;
    _confirm(size);
  }
}

class _CircleGuide extends StatelessWidget {
  const _CircleGuide();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CircleGuidePainter());
  }
}

class _CircleGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    final center = Offset(size.width / 2, size.height / 2);

    // Dim everything outside the circle: even-odd fills the square minus the
    // circle in one path, so the circle itself stays untouched.
    final shade = Path()
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: 0.5));

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
