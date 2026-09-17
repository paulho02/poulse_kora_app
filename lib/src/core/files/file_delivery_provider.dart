import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_delivery.dart';

/// The signature of [deliverFile], so a test can stand in for it.
typedef FileDeliverer =
    Future<FileDelivery> Function({
      required String filename,
      required Uint8List bytes,
      required String mimeType,
      Rect? shareOrigin,
    });

/// Handing a finished file to the person, behind a provider.
///
/// The real implementation reaches the share sheet on Android and the browser's
/// download on web - neither of which exists under `flutter test`, where the
/// platform channels are not registered and the answer to "did this work?" would
/// be a MissingPluginException rather than a verdict. An override here is what
/// lets a widget test assert the thing worth asserting: that the bytes the
/// server sent are the bytes handed on, under the name the server chose.
final fileDeliveryProvider = Provider<FileDeliverer>((ref) => deliverFile);
