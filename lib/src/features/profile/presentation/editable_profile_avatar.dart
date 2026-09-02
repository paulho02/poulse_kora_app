import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/avatars/presentation/user_avatar.dart';
import '../../../core/media/presentation/crop_media_screen.dart';
import '../../../core/presentation/error_state_view.dart';
import '../application/profile_providers.dart';
import '../data/user_profile.dart';
import 'crop_avatar_screen.dart';

/// The profile header's avatar, with editing attached.
///
/// This is the only place a profile picture is set. It lives on the picture
/// itself rather than in Settings: the profile view already shows the avatar, so
/// a separate settings row would be a second, less obvious answer to "where do I
/// change this?".
class EditableProfileAvatar extends ConsumerStatefulWidget {
  const EditableProfileAvatar({
    super.key,
    required this.profile,
    this.radius = 36,
  });

  final UserProfile profile;
  final double radius;

  @override
  ConsumerState<EditableProfileAvatar> createState() =>
      _EditableProfileAvatarState();
}

class _EditableProfileAvatarState extends ConsumerState<EditableProfileAvatar> {
  var _busy = false;

  Future<void> _pick() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);

    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Bounds how much has to be decoded and held in memory — a 50MP photo
        // would otherwise be fully decoded just to crop a 512px square out of
        // it. Still far more detail than the crop needs.
        maxWidth: 2048,
        maxHeight: 2048,
      );
    } catch (error) {
      // A denied gallery permission arrives here rather than as a null result.
      showErrorSnackBarOn(messenger, l10n, error);
      return;
    }
    // Null means the picker was dismissed — not an error.
    if (file == null) return;

    final ui.Image decoded;
    try {
      decoded = await decodeImageBytes(await file.readAsBytes());
    } catch (_) {
      // Flutter's own decoder rejecting the file is the format check: it covers
      // everything the app could actually display, which is a better question
      // than "does the extension look right?".
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.errorProfilePictureInvalidType),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    final CropResult? cropped;
    try {
      cropped = await navigator.push<CropResult>(
        MaterialPageRoute(
          builder: (_) => CropAvatarScreen(image: decoded),
          fullscreenDialog: true,
        ),
      );
    } finally {
      decoded.dispose();
    }
    // Backed out of the crop screen.
    if (cropped == null) return;

    await _upload(messenger, l10n, cropped.bytes);
  }

  Future<void> _upload(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
    Uint8List bytes,
  ) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(profileProvider.notifier)
          .setProfilePicture(
            bytes: bytes,
            filename: 'avatar.png',
            // Not sniffed or guessed: the crop screen always re-encodes to PNG,
            // so this describes the bytes by construction.
            contentType: 'image/png',
          );
      _toast(messenger, l10n.profilePictureUpdated);
    } catch (error) {
      showErrorSnackBarOn(messenger, l10n, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    setState(() => _busy = true);
    try {
      await ref.read(profileProvider.notifier).removeProfilePicture();
      _toast(messenger, l10n.profilePictureRemoved);
    } catch (error) {
      showErrorSnackBarOn(messenger, l10n, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _openSheet() async {
    final l10n = AppLocalizations.of(context);
    final hasPicture = widget.profile.profilePictureUrl != null;

    final action = await showModalBottomSheet<_PictureAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                hasPicture
                    ? l10n.profilePictureChange
                    : l10n.profilePictureChoose,
              ),
              onTap: () => Navigator.of(context).pop(_PictureAction.pick),
            ),
            if (hasPicture)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.profilePictureRemove),
                onTap: () => Navigator.of(context).pop(_PictureAction.remove),
              ),
          ],
        ),
      ),
    );

    switch (action) {
      case _PictureAction.pick:
        await _pick();
      case _PictureAction.remove:
        await _remove();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final profile = widget.profile;
    final name = profile.username ?? profile.email;
    final badgeRadius = widget.radius * 0.32;

    // Tooltip supplies the label and InkWell's onTap the button role, so no
    // extra Semantics wrapper — that would only duplicate the node.
    return Tooltip(
      message: l10n.profilePictureEditTooltip,
      child: InkWell(
        onTap: _busy ? null : () => unawaited(_openSheet()),
        customBorder: const CircleBorder(),
        child: Stack(
          children: [
            UserAvatar(
              imageUrl: profile.profilePictureUrl,
              radius: widget.radius,
              fallback: MonogramAvatar(seed: name, radius: widget.radius),
            ),
            // Dim the picture while the upload is in flight, so the tap has a
            // visible consequence on the thing that was tapped rather than
            // only somewhere else on screen.
            if (_busy)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.scrim.withValues(alpha: 0.45),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            // The affordance: without it, an avatar that is merely tappable
            // looks exactly like one that isn't.
            Positioned(
              right: 0,
              bottom: 0,
              child: CircleAvatar(
                radius: badgeRadius,
                backgroundColor: theme.colorScheme.primary,
                child: Icon(
                  Icons.photo_camera_outlined,
                  size: badgeRadius,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PictureAction { pick, remove }
