import 'dart:math' as math;

/// The two shapes every post attachment is published in.
///
/// Mirrors the backend's `POST_MEDIA_LANDSCAPE_RATIO` / `POST_MEDIA_PORTRAIT_RATIO`
/// (see its `app/core/config.py`), kept in sync manually — there is no config
/// endpoint carrying them. Getting them out of step is not silent: an image is
/// cropped here and *validated* there, so a mismatch surfaces as a
/// `post_media_invalid_aspect_ratio` rejection rather than a wrong-looking post.
///
/// A single-column feed reads far better when every post is one of two known
/// shapes: the layout is predictable, and a media block can reserve its box from
/// `PostMedia.width/height` before a single byte of the image has arrived.
const double kPostMediaLandscapeRatio = 4 / 3;
const double kPostMediaPortraitRatio = 4 / 5;

/// Longest side of a cropped photo before upload.
///
/// The cropper can only emit PNG (`Image.toByteData` offers no other compressed
/// format), so this is really a bandwidth budget: a post may carry up to five of
/// these. The backend re-encodes an opaque PNG to JPEG on arrival and allows up
/// to 2048px, so raising this buys detail only at real upload cost.
const int kPostCropLongestSide = 1280;

/// The orientation names the backend accepts on a media block
/// (`PostBlockIn.orientation`).
enum PostMediaOrientation {
  landscape,
  portrait;

  String get wireValue => name;

  double get ratio => this == PostMediaOrientation.landscape
      ? kPostMediaLandscapeRatio
      : kPostMediaPortraitRatio;
}

/// Which allowed shape [ratio] is closest to.
///
/// Used to preselect the crop frame for a photo, and to preselect the
/// orientation for a video, so the common case ("this is already roughly
/// landscape") is one confirmation rather than a decision.
///
/// Compared in log space, matching the backend's `nearest_orientation`: a linear
/// distance would quietly favour the portrait ratio, whose numeric value is the
/// smaller of the two.
PostMediaOrientation nearestPostOrientation(double ratio) {
  if (!ratio.isFinite || ratio <= 0) return PostMediaOrientation.portrait;
  final toLandscape = (math.log(ratio / kPostMediaLandscapeRatio)).abs();
  final toPortrait = (math.log(ratio / kPostMediaPortraitRatio)).abs();
  return toLandscape <= toPortrait
      ? PostMediaOrientation.landscape
      : PostMediaOrientation.portrait;
}
