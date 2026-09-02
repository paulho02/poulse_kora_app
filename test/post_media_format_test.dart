import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/src/core/media/post_media_format.dart';

void main() {
  group('nearestPostOrientation', () {
    test('an exact match picks its own shape', () {
      expect(
        nearestPostOrientation(kPostMediaLandscapeRatio),
        PostMediaOrientation.landscape,
      );
      expect(
        nearestPostOrientation(kPostMediaPortraitRatio),
        PostMediaOrientation.portrait,
      );
    });

    test('a 16:9 clip is landscape and a 9:16 one is portrait', () {
      expect(nearestPostOrientation(16 / 9), PostMediaOrientation.landscape);
      expect(nearestPostOrientation(9 / 16), PostMediaOrientation.portrait);
    });

    test('a square is judged proportionally, not by raw distance', () {
      // A square is 25% wider than 4:5 but 33% narrower than 4:3, so it belongs
      // with the upright shape. A linear distance would say the opposite
      // (0.2 away from 0.8, 0.33 away from 1.333 — same verdict here, but it
      // flips either side of the true crossover at ~1.033), which is why this
      // and the backend's `nearest_orientation` both compare in log space.
      expect(nearestPostOrientation(1.0), PostMediaOrientation.portrait);
      // Just past the crossover, the answer changes.
      expect(nearestPostOrientation(1.05), PostMediaOrientation.landscape);
    });

    test('a degenerate ratio falls back rather than throwing', () {
      expect(nearestPostOrientation(0), PostMediaOrientation.portrait);
      expect(nearestPostOrientation(double.nan), PostMediaOrientation.portrait);
    });
  });

  test('wireValue matches what the backend accepts', () {
    // PostBlockIn.orientation is a Literal["landscape", "portrait"], so a
    // rename here is a 422 there.
    expect(PostMediaOrientation.landscape.wireValue, 'landscape');
    expect(PostMediaOrientation.portrait.wireValue, 'portrait');
  });
}
