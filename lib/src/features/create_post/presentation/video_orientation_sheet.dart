import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/media/post_media_format.dart';

/// Asks which of the two published shapes a picked video should be cropped to.
///
/// A video gets a *choice* rather than the pan-and-zoom cropper a photo gets,
/// because a Flutter client has no video encoder — the crop itself happens
/// server-side, inside the transcode the backend already runs, and all it needs
/// from here is the orientation. The alternative (letting the server guess from
/// the source shape) is what this replaces: it worked, but the author only found
/// out what had been cut after publishing.
///
/// Returns null if dismissed, which cancels adding the clip.
Future<PostMediaOrientation?> showVideoOrientationSheet(BuildContext context) {
  return showModalBottomSheet<PostMediaOrientation>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      final l10n = AppLocalizations.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.composerVideoFormatTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.composerVideoFormatHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _FormatOption(
                      orientation: PostMediaOrientation.portrait,
                      label: l10n.composerFormatPortrait,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FormatOption(
                      orientation: PostMediaOrientation.landscape,
                      label: l10n.composerFormatLandscape,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A tappable card showing the shape itself at true ratio, rather than naming
/// it — "4:5" means nothing to most people, an actual tall rectangle does.
class _FormatOption extends StatelessWidget {
  const _FormatOption({required this.orientation, required this.label});

  final PostMediaOrientation orientation;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).pop(orientation),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 84,
              child: Center(
                child: AspectRatio(
                  aspectRatio: orientation.ratio,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                    child: Icon(
                      Icons.videocam_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(label, style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}
