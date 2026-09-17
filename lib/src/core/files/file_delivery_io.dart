import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'file_delivery_result.dart';

/// Where exported files are staged before the share sheet picks them up.
///
/// A folder of our own inside the cache directory, so the cleanup below can
/// empty it without having to guess which of the cache's files are ours.
const _stagingFolder = 'exports';

/// Hand [bytes] to the person, on platforms with a filesystem (Android today).
///
/// There is no directory an Android app may write to that a person can then
/// find - `getExternalStorageDirectory()` is app-scoped and buried - so the file
/// is staged in the app's own cache and the system share sheet is what actually
/// delivers it, to Drive, to Files, to a mail draft, to whatever they use.
///
/// **The staging folder is emptied first, not afterwards.** The receiving app
/// reads the file asynchronously after the sheet closes, so deleting it on the
/// way out is a race that ends in a zero-byte file in somebody's Drive. Clearing
/// on the way *in* keeps at most one export on the device instead, which matters
/// here more than it would for any other file this app writes: it is a copy of
/// an entire account's personal data sitting in a cache.
Future<FileDelivery> deliverFile({
  required String filename,
  required Uint8List bytes,
  required String mimeType,
  Rect? shareOrigin,
}) async {
  final staging = Directory(
    '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}'
    '$_stagingFolder',
  );
  if (staging.existsSync()) {
    staging.deleteSync(recursive: true);
  }
  staging.createSync(recursive: true);

  final file = File('${staging.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);

  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType, name: filename)],
      fileNameOverrides: [filename],
      // iPads anchor the popover to this; ignored everywhere else, and passing
      // null only costs a sheet centred on the screen rather than a crash.
      sharePositionOrigin: shareOrigin,
    ),
  );
  // `unavailable` is Android saying it shared but cannot report where to - the
  // common case, and success as far as anyone using the app is concerned.
  return result.status == ShareResultStatus.dismissed
      ? FileDelivery.dismissed
      : FileDelivery.handedOff;
}
