import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'file_delivery_result.dart';

/// Hand [bytes] to the person, in a browser.
///
/// The browser's own download, rather than the Web Share API: sharing files is
/// unevenly supported, is refused outside a user gesture in several browsers,
/// and would put a file that is one person's entire personal data into an app
/// picker when what they asked for was a copy of it. A download goes exactly
/// where that browser puts downloads, which is the thing they already know.
///
/// The object URL is revoked immediately. That is safe because `click()` on a
/// same-document anchor starts the download synchronously, and leaving it alive
/// would pin the whole archive in memory for the life of the tab.
Future<FileDelivery> deliverFile({
  required String filename,
  required Uint8List bytes,
  required String mimeType,
  Rect? shareOrigin,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  // Not added to the document: a detached anchor's click still triggers the
  // download in every browser this app supports, and nothing has to be cleaned
  // up out of the DOM afterwards.
  anchor.click();
  web.URL.revokeObjectURL(url);
  return FileDelivery.handedOff;
}
