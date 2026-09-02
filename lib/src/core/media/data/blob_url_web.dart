import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Wraps `bytes` in a same-origin `blob:` URL the browser can play without any
/// request (headers included) ever leaving the page - see `videoSourceFor` in
/// `media_video_source.dart` for why this exists.
String createBlobUrl(Uint8List bytes, String mimeType) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  return web.URL.createObjectURL(blob);
}

/// Releases the underlying bytes. `createBlobUrl` bytes are only ever handed
/// to one `VideoPlayerController`, so this is safe to call the moment that
/// controller is disposed.
void revokeBlobUrl(String url) => web.URL.revokeObjectURL(url);
