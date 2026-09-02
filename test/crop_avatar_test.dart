import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/src/core/media/presentation/crop_geometry.dart';

void main() {
  group('cropSourceRect', () {
    test('an untouched square image crops to the whole image', () {
      final rect = cropSourceRect(
        transform: Matrix4.identity(),
        viewport: const Size.square(300),
        imageSize: const Size(100, 100),
      );
      expect(rect, const Rect.fromLTRB(0, 0, 100, 100));
    });

    test('a wide image starts framed on its centre, not its left edge', () {
      // BoxFit.cover on a 200x100 image in a square viewport shows the middle
      // 100x100 of it. Getting this wrong would silently crop everyone's
      // picture off to one side.
      final rect = cropSourceRect(
        transform: Matrix4.identity(),
        viewport: const Size.square(100),
        imageSize: const Size(200, 100),
      );
      expect(rect, const Rect.fromLTRB(50, 0, 150, 100));
    });

    test('a tall image starts framed on its centre too', () {
      final rect = cropSourceRect(
        transform: Matrix4.identity(),
        viewport: const Size.square(100),
        imageSize: const Size(100, 400),
      );
      expect(rect, const Rect.fromLTRB(0, 150, 100, 250));
    });

    test('zooming in narrows the framed region proportionally', () {
      // Scaling about the origin puts the viewport over the child's top-left
      // quarter, so exactly a quarter of the source is kept.
      final rect = cropSourceRect(
        transform: Matrix4.identity()..scaleByDouble(2.0, 2.0, 1.0, 1.0),
        viewport: const Size.square(100),
        imageSize: const Size(100, 100),
      );
      expect(rect, const Rect.fromLTRB(0, 0, 50, 50));
    });

    test('panning moves the framed region', () {
      // A translation of -20 in child space shifts what is on screen by +20.
      final rect = cropSourceRect(
        transform: Matrix4.identity()
          ..scaleByDouble(2.0, 2.0, 1.0, 1.0)
          ..translateByDouble(-20.0, -10.0, 0.0, 1.0),
        viewport: const Size.square(100),
        imageSize: const Size(100, 100),
      );
      expect(rect, const Rect.fromLTRB(20, 10, 70, 60));
    });

    test('the region never escapes the image, whatever the transform', () {
      // The viewer bounds panning to the child, not to the image's letterboxed
      // area inside it — so without clamping a wide image could yield negative
      // coordinates and `drawImageRect` would sample outside the bitmap.
      final rect = cropSourceRect(
        transform: Matrix4.identity()
          ..translateByDouble(500.0, 500.0, 0.0, 1.0),
        viewport: const Size.square(100),
        imageSize: const Size(200, 100),
      );
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(200));
      expect(rect.bottom, lessThanOrEqualTo(100));
    });

    test('the framed region is square for a square viewport', () {
      // The output is drawn into a square, so a non-square source region would
      // stretch the picture.
      final rect = cropSourceRect(
        transform: Matrix4.identity()..scaleByDouble(1.7, 1.7, 1.0, 1.0),
        viewport: const Size.square(100),
        imageSize: const Size(640, 480),
      );
      expect(rect.width, closeTo(rect.height, 0.0001));
    });
  });
}
