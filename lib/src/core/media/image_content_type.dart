import 'dart:typed_data';

/// The content type of [bytes], read from the bytes themselves, or `null` if
/// they are not one of the three image formats the backend accepts.
///
/// Exists for the one upload path that does **not** go through
/// `CropMediaScreen`: feedback attachments. Post photos and avatars are
/// re-encoded by the cropper, which is what makes their declared content type
/// true by construction — a screenshot has no crop to apply, and re-encoding one
/// anyway would either turn a JPEG photo into a needlessly huge PNG or a PNG
/// screenshot into a JPEG with ringing around exactly the text being reported.
///
/// Sniffing is as truthful as declaring: both answer "what are these bytes",
/// and the backend re-derives the type from what its decoder actually parsed
/// either way (`app/core/media_validation.py`). What this buys is that the
/// original encoding survives the trip, and that an unsupported file (a HEIC the
/// picker did not convert) is caught here, with a message, rather than as a 400
/// after the upload.
String? sniffImageContentType(Uint8List bytes) {
  if (_startsWith(bytes, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  // RIFF....WEBP — the four bytes between are the file size, so they are skipped
  // rather than matched.
  if (_startsWith(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
      bytes.length >= 12 &&
      _startsWith(bytes.sublist(8, 12), const [0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  return null;
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}
