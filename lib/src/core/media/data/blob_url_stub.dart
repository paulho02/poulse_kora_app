import 'dart:typed_data';

/// Never actually called - `videoSourceFor` only reaches this branch under
/// `kIsWeb`, and this stub is what non-web builds compile against instead of
/// `blob_url_web.dart` (which imports `package:web`, web-only).
String createBlobUrl(Uint8List bytes, String mimeType) =>
    throw UnsupportedError('Blob URLs only exist on web.');

void revokeBlobUrl(String url) {}
