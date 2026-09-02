import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import 'crop_geometry.dart';

/// One shape the user may crop to. A screen given a single aspect just frames
/// it; given several, it shows a picker and re-frames on every change.
class CropAspect {
  const CropAspect({
    required this.ratio,
    required this.label,
    required this.icon,
  });

  final double ratio;
  final String label;
  final IconData icon;
}

/// What [CropMediaScreen] pops on save.
class CropResult {
  const CropResult({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  double get aspectRatio => width / height;
}

/// Whether to draw the circular avatar guide over the frame.
enum CropOverlay { none, circle }

/// Decode picked bytes into something [CropMediaScreen] can draw.
///
/// Flutter's own decoder rejecting the bytes is the format check, for both
/// croppers: it covers exactly what the app could actually display, which is a
/// better question than "does the extension look right?".
Future<ui.Image> decodeImageBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

/// Pan-and-zoom crop, shown after picking an image — for an avatar (one square
/// aspect, circular guide) and for a post photo (a landscape/portrait choice).
///
/// Producing the bytes here rather than uploading what the picker returned is
/// what makes the result predictable, and it is the *only* thing that does:
/// `image_picker` re-encodes differently per platform (its web resizer goes
/// through a canvas and emits PNG; Android emits JPEG), so without this step the
/// format — and the content type we would have to declare for it — depended on
/// where the app was running. It also fixes the shape, which the backend
/// requires of a post photo: it validates the aspect ratio and rejects anything
/// else outright (`post_media_invalid_aspect_ratio`) rather than cropping
/// server-side, because this screen is the only place that can show an author
/// what a crop is about to discard.
///
/// Always emits PNG — `Image.toByteData` offers no other compressed format. The
/// backend re-encodes an opaque one to JPEG on arrival, so the size costs
/// upload bandwidth once and nothing in storage.
class CropMediaScreen extends StatefulWidget {
  const CropMediaScreen({
    super.key,
    required this.image,
    required this.aspects,
    required this.title,
    required this.hint,
    this.overlay = CropOverlay.none,
    this.outputLongestSide = 1280,
    this.initialAspectIndex = 0,
  }) : assert(aspects.length > 0);

  final ui.Image image;
  final List<CropAspect> aspects;
  final String title;
  final String hint;
  final CropOverlay overlay;

  /// Longest side of the produced image. Bounds the upload: a PNG this size is
  /// a few MB, and a post may carry several.
  final int outputLongestSide;
  final int initialAspectIndex;

  @override
  State<CropMediaScreen> createState() => _CropMediaScreenState();
}

class _CropMediaScreenState extends State<CropMediaScreen> {
  late int _aspectIndex = widget.initialAspectIndex.clamp(
    0,
    widget.aspects.length - 1,
  );
  TransformationController _controller = TransformationController();
  var _saving = false;

  /// The frame the user actually saw, recorded by the LayoutBuilder below. The
  /// crop maths has to run against it, so it is read from layout rather than
  /// re-derived from MediaQuery — the frame is sized by what the controls leave
  /// over, which MediaQuery alone doesn't know.
  Size? _viewport;

  CropAspect get _aspect => widget.aspects[_aspectIndex];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectAspect(int index) {
    if (index == _aspectIndex) return;
    setState(() {
      _aspectIndex = index;
      // A transform is expressed in the old frame's coordinates, so carrying it
      // across a reshape would frame a region the user never chose — and, since
      // panning is bounded to the child, could strand them outside the image.
      _controller.dispose();
      _controller = TransformationController();
    });
  }

  Future<void> _save() async {
    final viewport = _viewport;
    // Only null if the frame never laid out, which cannot happen while the
    // button beside it is on screen.
    if (viewport == null || viewport.isEmpty) return;
    setState(() => _saving = true);
    final result = await _render(viewport);
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  /// Map the visible part of the frame back to source pixels, then draw just
  /// that region into a fixed-size output of the chosen shape.
  Future<CropResult?> _render(Size viewport) async {
    final image = widget.image;
    final src = cropSourceRect(
      transform: _controller.value,
      viewport: viewport,
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
    );
    // A degenerate rect would make `drawImageRect` throw rather than produce a
    // blank picture; nothing sane should reach it, but the crop is user-driven.
    if (src.width <= 0 || src.height <= 0) return null;

    final out = outputSizeFor(_aspect.ratio, widget.outputLongestSide);
    final width = out.width.round();
    final height = out.height.round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(0, 0, out.width, out.height),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(width, height);
    picture.dispose();
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    final bytes = data?.buffer.asUint8List();
    if (bytes == null) return null;
    return CropResult(bytes: bytes, width: width, height: height);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = fitAspectRatio(
                      Size(constraints.maxWidth, constraints.maxHeight),
                      _aspect.ratio,
                    );
                    _viewport = size;
                    return SizedBox(
                      width: size.width,
                      height: size.height,
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
                              width: size.width,
                              height: size.height,
                              child: RawImage(
                                image: widget.image,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _GuidePainter(
                                circle: widget.overlay == CropOverlay.circle,
                              ),
                            ),
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
                  if (widget.aspects.length > 1) ...[
                    _AspectPicker(
                      aspects: widget.aspects,
                      selectedIndex: _aspectIndex,
                      onSelected: _saving ? null : _selectAspect,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    widget.hint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
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
                          onPressed: _saving ? null : _save,
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
}

/// Landscape/portrait switch. A segmented button rather than a free rotation
/// control: the two shapes are the only ones the backend accepts, so offering
/// anything continuous would just be a way to compose a rejected upload.
class _AspectPicker extends StatelessWidget {
  const _AspectPicker({
    required this.aspects,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<CropAspect> aspects;
  final int selectedIndex;
  final void Function(int)? onSelected;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: [
        for (var i = 0; i < aspects.length; i++)
          ButtonSegment(
            value: i,
            icon: Icon(aspects[i].icon),
            label: Text(aspects[i].label),
          ),
      ],
      selected: {selectedIndex},
      showSelectedIcon: false,
      onSelectionChanged: onSelected == null
          ? null
          : (selection) => onSelected!(selection.first),
    );
  }
}

/// Guides drawn over the frame — never baked into the saved image.
///
/// For an avatar the circle shows what survives the circular crop every avatar
/// in the app applies when displaying it. For a post photo there is no such
/// second crop, so it gets rule-of-thirds lines instead: the whole frame is
/// kept, and the only thing worth helping with is placing the subject.
class _GuidePainter extends CustomPainter {
  const _GuidePainter({required this.circle});

  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    if (circle) {
      final radius = size.shortestSide / 2;
      final center = Offset(size.width / 2, size.height / 2);

      // Dim everything outside the circle: even-odd fills the square minus the
      // circle in one path, so the circle itself stays untouched.
      final shade = Path()
        ..addRect(Offset.zero & size)
        ..addOval(Rect.fromCircle(center: center, radius: radius))
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(
        shade,
        Paint()..color = Colors.black.withValues(alpha: 0.5),
      );

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.9),
      );
      return;
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.35);
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      oldDelegate.circle != circle;
}
