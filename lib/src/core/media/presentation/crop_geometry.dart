import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Which rectangle of the *source image*, in pixels, is currently framed by the
/// crop viewport.
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
///
/// [viewport] is a full [Size] rather than one side: the avatar cropper frames a
/// square, but a post's photo is framed at 4:3 or 4:5, and the returned region
/// has to match whatever shape the user was actually shown or the saved image is
/// stretched.
Rect cropSourceRect({
  required Matrix4 transform,
  required Size viewport,
  required Size imageSize,
}) {
  final coverScale = math.max(
    viewport.width / imageSize.width,
    viewport.height / imageSize.height,
  );
  final dx = (viewport.width - imageSize.width * coverScale) / 2;
  final dy = (viewport.height - imageSize.height * coverScale) / 2;

  final inverse = Matrix4.inverted(transform);
  final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
  final bottomRight = MatrixUtils.transformPoint(
    inverse,
    Offset(viewport.width, viewport.height),
  );

  return Rect.fromLTRB(
    ((topLeft.dx - dx) / coverScale).clamp(0.0, imageSize.width),
    ((topLeft.dy - dy) / coverScale).clamp(0.0, imageSize.height),
    ((bottomRight.dx - dx) / coverScale).clamp(0.0, imageSize.width),
    ((bottomRight.dy - dy) / coverScale).clamp(0.0, imageSize.height),
  );
}

/// The largest box of [aspectRatio] that fits inside [available] — the frame the
/// cropper draws, and the shape the crop is taken in.
Size fitAspectRatio(Size available, double aspectRatio) {
  var width = available.width;
  var height = width / aspectRatio;
  if (height > available.height) {
    height = available.height;
    width = height * aspectRatio;
  }
  return Size(width, height);
}

/// Output pixel size for a crop of [aspectRatio] whose longest side is
/// [longestSide]. Rounded to whole pixels, which is why the backend's ratio
/// check carries a tolerance rather than demanding an exact match.
Size outputSizeFor(double aspectRatio, int longestSide) {
  if (aspectRatio >= 1) {
    return Size(
      longestSide.toDouble(),
      (longestSide / aspectRatio).roundToDouble(),
    );
  }
  return Size(
    (longestSide * aspectRatio).roundToDouble(),
    longestSide.toDouble(),
  );
}
