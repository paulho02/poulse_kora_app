import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/media/image_content_type.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../auth/application/auth_providers.dart';
import '../application/feedback_providers.dart';
import '../data/feedback_repository.dart';

/// Kept in sync by hand with the backend's FEEDBACK_MEDIA_MAX_FILES and
/// FEEDBACK_MESSAGE_MAX_LENGTH — there is no config endpoint exposing them, and
/// both are enforced server-side regardless. These only stop the form from
/// building a submission that is certain to be rejected.
const _kMaxAttachments = 5;
const _kMaxMessageLength = 4000;

/// A precondition the submission hasn't met yet.
///
/// Held as a case rather than as resolved text, so a locale change can't strand
/// it — same reason as the composer's `_PublishBlocker`, and shown the same way:
/// a line above the button rather than a snackbar, since the button is at the
/// bottom of the screen and a snackbar would be drawn over it.
enum _SubmitBlocker { emptyMessage, noConsent }

/// The in-app feedback / bug report form.
///
/// Reachable from the profile **and from the login and register screens**, which
/// is the constraint the whole screen is built around: it has to work with no
/// account. Two things follow, and both are enforced by the backend as well as
/// shown here — the form is a convenience, not the guard:
///
/// - **Signed out, the submission is anonymous and there is nothing to answer
///   to.** The anonymity switch is shown checked and locked rather than hidden,
///   so the state is visible rather than merely implied, and "let us contact
///   you" is not offered at all — there is no verified address to contact.
/// - **Anonymous means anonymous.** The backend stores no `user_id` at all for
///   such a submission rather than storing one and hiding it, so choosing it
///   really does cut the link, and the contact option disappears with it.
///
/// Consent is a hard precondition: without it the button reports what is
/// missing and nothing is sent. The *time* of that consent is stamped by the
/// server, not by this screen.
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _messageController = TextEditingController();
  final _attachments = <FeedbackAttachment>[];

  var _kind = FeedbackKind.feedback;
  int? _rating;
  var _isAnonymous = false;
  var _allowContact = false;
  var _consent = false;
  var _submitting = false;
  _SubmitBlocker? _blocker;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  bool get _loggedIn => ref.read(authNotifierProvider).value ?? false;

  /// Signed out there is no identity to withhold and no address to reply to, so
  /// the effective values are fixed regardless of what the switches last held.
  bool get _effectiveAnonymous => _loggedIn ? _isAnonymous : true;
  bool get _effectiveAllowContact => _effectiveAnonymous ? false : _allowContact;

  int get _remainingSlots => _kMaxAttachments - _attachments.length;

  void _onKindChanged(FeedbackKind kind) {
    setState(() {
      _kind = kind;
      // The backend *rejects* a rating on any other kind rather than dropping
      // it, so the value has to go when the stars do.
      if (!kind.supportsRating) _rating = null;
    });
  }

  Future<void> _addPhotos() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (_remainingSlots <= 0) return;

    final List<XFile> files;
    try {
      // Deliberately no maxWidth/maxHeight: those make image_picker re-encode,
      // which on Android means a PNG screenshot arrives as a JPEG with ringing
      // around exactly the text and UI edges being reported. The backend caps
      // the size and downscales instead, and says so specifically if a photo is
      // too large.
      files = await ImagePicker().pickMultiImage(limit: _remainingSlots);
    } catch (error) {
      showErrorSnackBarOn(messenger, l10n, error);
      return;
    }
    if (files.isEmpty) return;

    final added = <FeedbackAttachment>[];
    for (final file in files.take(_remainingSlots)) {
      final bytes = await file.readAsBytes();
      // Read from the bytes, not from the picker's `mimeType` (routinely null)
      // or the extension. Also the local check for a format the backend cannot
      // decode — a HEIC the picker didn't convert — caught here with a message
      // rather than as a 400 after the upload.
      final contentType = sniffImageContentType(bytes);
      if (contentType == null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(l10n.errorFeedbackMediaInvalidType)),
          );
        continue;
      }
      added.add(
        FeedbackAttachment(
          bytes: bytes,
          filename: file.name,
          contentType: contentType,
          isVideo: false,
        ),
      );
    }

    if (!mounted || added.isEmpty) return;
    setState(() => _attachments.addAll(added));
  }

  Future<void> _addVideo() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (_remainingSlots <= 0) return;

    final XFile? file;
    try {
      file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    } catch (error) {
      showErrorSnackBarOn(messenger, l10n, error);
      return;
    }
    if (file == null) return;
    final picked = file;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    setState(() {
      _attachments.add(
        FeedbackAttachment(
          bytes: bytes,
          filename: picked.name,
          contentType: _guessVideoContentType(picked),
          isVideo: true,
        ),
      );
    });
  }

  Future<void> _submit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      setState(() => _blocker = _SubmitBlocker.emptyMessage);
      return;
    }
    if (!_consent) {
      setState(() => _blocker = _SubmitBlocker.noConsent);
      return;
    }

    // Captured before the await: this screen pops itself on success, so by the
    // time the confirmation is shown `context` is gone.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    // `Navigator`, not `GoRouter.of` — this screen is pushed as an ordinary
    // page, so it needs nothing from go_router, and depending on one would make
    // it unmountable anywhere without a router above it (its own widget test
    // included).
    final navigator = Navigator.of(context);

    setState(() {
      _blocker = null;
      _submitting = true;
    });
    try {
      await ref
          .read(feedbackRepositoryProvider)
          .submit(
            kind: _kind,
            message: message,
            consent: true,
            isAnonymous: _effectiveAnonymous,
            allowContact: _effectiveAllowContact,
            rating: _rating,
            attachments: _attachments,
          );
    } catch (error) {
      if (mounted) setState(() => _submitting = false);
      showErrorSnackBarOn(messenger, l10n, error);
      return;
    }

    if (mounted) setState(() => _submitting = false);
    // Leaving the screen is the confirmation; the snackbar is the receipt. The
    // form is not cleared first — popping discards it either way, and clearing
    // it would flash an empty form during the transition.
    if (navigator.canPop()) navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.feedbackSubmitted),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final loggedIn = ref.watch(authNotifierProvider).value ?? false;
    final anonymous = loggedIn ? _isAnonymous : true;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.feedbackTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(l10n.feedbackIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),

          Text(l10n.feedbackKindLabel, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in FeedbackKind.values)
                ChoiceChip(
                  label: Text(_kindLabel(l10n, kind)),
                  selected: _kind == kind,
                  onSelected: _submitting
                      ? null
                      : (selected) {
                          if (selected) _onKindChanged(kind);
                        },
                ),
            ],
          ),

          // Only for plain feedback — a bug report has nothing to score, and the
          // backend refuses a rating sent with any other kind.
          if (_kind.supportsRating) ...[
            const SizedBox(height: 20),
            Text(l10n.feedbackRatingLabel, style: theme.textTheme.labelLarge),
            _StarRating(
              rating: _rating,
              enabled: !_submitting,
              onChanged: (value) => setState(() => _rating = value),
            ),
          ],

          const SizedBox(height: 20),
          TextField(
            controller: _messageController,
            enabled: !_submitting,
            minLines: 5,
            maxLines: 10,
            maxLength: _kMaxMessageLength,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.feedbackMessageLabel,
              hintText: _messageHint(l10n, _kind),
              alignLabelWithHint: true,
            ),
            // The "say something first" line is only stale once there is
            // something, so it clears with the typing rather than on the next
            // press of the button.
            onChanged: (_) {
              if (_blocker == _SubmitBlocker.emptyMessage) {
                setState(() => _blocker = null);
              }
            },
          ),

          const SizedBox(height: 8),
          _AttachmentsSection(
            attachments: _attachments,
            enabled: !_submitting,
            onAddPhotos: _addPhotos,
            onAddVideo: _addVideo,
            onRemove: (index) => setState(() => _attachments.removeAt(index)),
          ),

          const Divider(height: 32),

          CheckboxListTile(
            value: anonymous,
            // Locked rather than hidden when signed out, so "this is anonymous"
            // is something the screen states rather than something the reader
            // has to infer from the absence of a control.
            onChanged: (!loggedIn || _submitting)
                ? null
                : (value) => setState(() {
                    _isAnonymous = value ?? false;
                    if (_isAnonymous) _allowContact = false;
                  }),
            title: Text(l10n.feedbackAnonymousLabel),
            subtitle: Text(
              loggedIn
                  ? l10n.feedbackAnonymousHint
                  : l10n.feedbackAnonymousSignedOutHint,
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),

          // There is nothing to contact an anonymous submission at — the backend
          // stores no address for one, and refuses the combination outright.
          if (!anonymous)
            CheckboxListTile(
              value: _allowContact,
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _allowContact = value ?? false),
              title: Text(l10n.feedbackAllowContactLabel),
              subtitle: Text(l10n.feedbackAllowContactHint),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),

          CheckboxListTile(
            value: _consent,
            onChanged: _submitting
                ? null
                : (value) => setState(() {
                    _consent = value ?? false;
                    if (_consent && _blocker == _SubmitBlocker.noConsent) {
                      _blocker = null;
                    }
                  }),
            title: Text(l10n.feedbackConsentLabel),
            subtitle: Text(l10n.feedbackConsentHint),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),

          if (_blocker != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    switch (_blocker!) {
                      _SubmitBlocker.emptyMessage => l10n.feedbackBlockerMessage,
                      _SubmitBlocker.noConsent => l10n.feedbackBlockerConsent,
                    },
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          FilledButton(
            // Never disabled by an unmet precondition — pressing it is how the
            // reader finds out what is missing, which a greyed-out button never
            // tells them.
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.feedbackSubmit),
          ),
        ],
      ),
    );
  }
}

/// Only videos need guessing: an image's type is read from its own bytes
/// (`sniffImageContentType`), which there is no equivalent of here — the backend
/// re-derives it with ffprobe and normalizes every clip to mp4 anyway.
String _guessVideoContentType(XFile file) {
  final mime = file.mimeType;
  if (mime != null) return mime;
  return file.name.split('.').last.toLowerCase() == 'mov'
      ? 'video/quicktime'
      : 'video/mp4';
}

String _kindLabel(AppLocalizations l10n, FeedbackKind kind) => switch (kind) {
  FeedbackKind.feedback => l10n.feedbackKindFeedback,
  FeedbackKind.bug => l10n.feedbackKindBug,
  FeedbackKind.featureRequest => l10n.feedbackKindFeatureRequest,
  FeedbackKind.other => l10n.feedbackKindOther,
};

/// The prompt is per kind: "what happened, and what did you expect?" is a much
/// better question for a bug than the generic one, and asking it in the field
/// itself costs no extra chrome.
String _messageHint(AppLocalizations l10n, FeedbackKind kind) => switch (kind) {
  FeedbackKind.bug => l10n.feedbackMessageHintBug,
  FeedbackKind.featureRequest => l10n.feedbackMessageHintFeature,
  _ => l10n.feedbackMessageHintGeneric,
};

class _StarRating extends StatelessWidget {
  const _StarRating({
    required this.rating,
    required this.enabled,
    required this.onChanged,
  });

  final int? rating;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        for (var star = 1; star <= 5; star++)
          IconButton(
            // Tapping the current rating clears it, so a star given by accident
            // is undoable — there is no other way back to "no rating", and the
            // backend treats that as a real state rather than as zero.
            onPressed: enabled
                ? () => onChanged(rating == star ? null : star)
                : null,
            tooltip: l10n.feedbackRatingStars(star),
            icon: Icon(
              (rating ?? 0) >= star ? Icons.star : Icons.star_border,
              color: (rating ?? 0) >= star
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _AttachmentsSection extends StatelessWidget {
  const _AttachmentsSection({
    required this.attachments,
    required this.enabled,
    required this.onAddPhotos,
    required this.onAddVideo,
    required this.onRemove,
  });

  final List<FeedbackAttachment> attachments;
  final bool enabled;
  final VoidCallback onAddPhotos;
  final VoidCallback onAddVideo;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final canAdd = enabled && attachments.length < _kMaxAttachments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.feedbackAttachmentsLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          l10n.feedbackAttachmentsHint(_kMaxAttachments),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: attachments.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _AttachmentThumbnail(
                attachment: attachments[index],
                onRemove: enabled ? () => onRemove(index) : null,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: canAdd ? onAddPhotos : null,
              icon: const Icon(Icons.image_outlined),
              label: Text(l10n.feedbackAddPhoto),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: canAdd ? onAddVideo : null,
              icon: const Icon(Icons.videocam_outlined),
              label: Text(l10n.feedbackAddVideo),
            ),
          ],
        ),
      ],
    );
  }
}

class _AttachmentThumbnail extends StatelessWidget {
  const _AttachmentThumbnail({required this.attachment, this.onRemove});

  final FeedbackAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: attachment.isVideo
                // No poster to show: the frame the backend extracts exists only
                // after the upload, and decoding one locally would mean holding
                // a video decoder open for a thumbnail.
                ? ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.movie_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Image.memory(attachment.bytes, fit: BoxFit.cover),
          ),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: Material(
                color: theme.colorScheme.surface.withValues(alpha: 0.8),
                shape: const CircleBorder(),
                child: IconButton(
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  tooltip: l10n.feedbackRemoveAttachment,
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
