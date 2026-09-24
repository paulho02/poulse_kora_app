import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peerkola/src/core/media/presentation/crop_geometry.dart';

void main() {
  group('cropSourceRect with a non-square frame', () {
    test('a 4:5 frame takes a 4:5 region out of a landscape photo', () {
      // The output is drawn into a 4:5 box, so a region of any other shape
      // would stretch the picture — the failure mode that made this worth
      // testing separately from the square avatar case.
      final rect = cropSourceRect(
        transform: Matrix4.identity(),
        viewport: const Size(80, 100),
        imageSize: const Size(400, 300),
      );
      expect(rect.width / rect.height, closeTo(0.8, 0.0001));
    });

    test('a 4:3 frame starts centred on a tall photo', () {
      // BoxFit.cover fits the width, so the frame shows the middle band.
      final rect = cropSourceRect(
        transform: Matrix4.identity(),
        viewport: const Size(400, 300),
        imageSize: const Size(400, 800),
      );
      expect(rect.left, 0);
      expect(rect.right, 400);
      expect(rect.center.dy, closeTo(400, 0.0001));
      expect(rect.width / rect.height, closeTo(4 / 3, 0.0001));
    });

    test('the region never escapes the image, whatever the transform', () {
      final rect = cropSourceRect(
        transform: Matrix4.identity()..translateByDouble(900, 900, 0, 1),
        viewport: const Size(80, 100),
        imageSize: const Size(400, 300),
      );
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(400));
      expect(rect.bottom, lessThanOrEqualTo(300));
    });
  });

  group('fitAspectRatio', () {
    test('a wide shape is limited by the available width', () {
      expect(fitAspectRatio(const Size(300, 500), 4 / 3), const Size(300, 225));
    });

    test('a tall shape is limited by the available height', () {
      expect(fitAspectRatio(const Size(300, 200), 4 / 5), const Size(160, 200));
    });
  });

  group('outputSizeFor', () {
    test('landscape puts the long side on the width', () {
      expect(outputSizeFor(4 / 3, 1280), const Size(1280, 960));
    });

    test('portrait puts the long side on the height', () {
      expect(outputSizeFor(4 / 5, 1280), const Size(1024, 1280));
    });

    test('both shapes land within the backend ratio tolerance', () {
      // The backend rejects anything outside 2% of an allowed ratio
      // (POST_MEDIA_RATIO_TOLERANCE), and these sizes are rounded to whole
      // pixels — so the rounding has to stay well inside that.
      for (final ratio in [4 / 3, 4 / 5]) {
        final size = outputSizeFor(ratio, 1280);
        expect((size.width / size.height) / ratio - 1, closeTo(0, 0.02));
      }
    });
  });
}
