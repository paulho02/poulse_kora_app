import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/media/presentation/crop_media_screen.dart';

/// Side length of the image this screen produces. An avatar is drawn at 72px at
/// its largest, so 512 is generous even on a high-DPI screen, and a PNG that
/// size lands far inside the backend's 2 MB limit.
const int _outputSize = 512;

/// The avatar case of [CropMediaScreen]: one fixed square shape, no shape
/// picker, and the circular guide showing what survives the circular crop every
/// avatar in the app applies when displaying it.
///
/// The crop itself — geometry, rendering, always re-encoding to PNG — is shared
/// with the post-photo cropper rather than duplicated. See [CropMediaScreen] for
/// why re-encoding here (and not forwarding what `image_picker` returned) is
/// what makes the declared content type true.
class CropAvatarScreen extends StatelessWidget {
  const CropAvatarScreen({super.key, required this.image});

  final ui.Image image;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CropMediaScreen(
      image: image,
      // A single aspect hides the picker, so the label is never rendered.
      aspects: const [CropAspect(ratio: 1, label: '', icon: Icons.crop_square)],
      overlay: CropOverlay.circle,
      outputLongestSide: _outputSize,
      title: l10n.cropAvatarTitle,
      hint: l10n.cropAvatarHint,
    );
  }
}
