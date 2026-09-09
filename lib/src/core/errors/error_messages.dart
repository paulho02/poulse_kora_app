import '../../../l10n/generated/app_localizations.dart';
import 'api_exception.dart';

/// Single place where a failure becomes something a person can read.
///
/// Keyed on the backend's machine-readable `detail.error` code (see
/// `backend/app/core/errors.py`), so adding a new server-side error means adding
/// one case here rather than hunting through screens. Never render an exception's
/// `toString()` at a call site — that is what produced the raw Dio dumps this
/// replaces.
///
/// Takes [AppLocalizations] rather than a `BuildContext` so this stays a pure,
/// widget-free function — every call site already has a `context` in scope to
/// resolve `AppLocalizations.of(context)!` from.
String messageFor(AppLocalizations l10n, Object? rawError) {
  // Unwrap first: `AsyncValue.guard` hands widgets the raw `DioException` that
  // Dio rethrows, not the normalized failure inside it.
  final error = asRelayException(rawError);

  switch (error.error) {
    // ---- connectivity -------------------------------------------------------
    case 'offline':
      return l10n.errorOffline;
    case 'timeout':
      return l10n.errorTimeout;

    // ---- auth -----------------------------------------------------------------
    case 'login_bad_credentials':
      return l10n.errorLoginBadCredentials;
    case 'register_user_already_exists':
    case 'update_user_email_already_exists':
      return l10n.errorEmailAlreadyExists;
    // Raised by registration *and* by the onboarding username step, which is why
    // it is one code rather than a per-route pair like the email ones above.
    // Both screens also render it under the username field itself; this is the
    // fallback for anywhere that only has a snackbar.
    case 'username_taken':
      return l10n.errorUsernameTaken;
    case 'register_invalid_password':
    case 'update_user_invalid_password':
    case 'change_password_invalid_password':
      return _passwordErrorMessage(l10n, error.detail['reason']);
    case 'change_password_wrong_current_password':
      return l10n.errorChangePasswordWrongCurrentPassword;

    // ---- google sign-in ------------------------------------------------------
    // `google_link_required` is deliberately absent: it is a prompt, not a
    // failure, and `GoogleAuthSection` turns it into a confirmation dialog
    // before it could ever reach a snackbar.
    case 'login_use_google':
      return l10n.errorLoginUseGoogle;
    case 'google_account_no_password':
      return l10n.errorGoogleAccountNoPassword;
    case 'google_account_email_locked':
      return l10n.errorGoogleAccountEmailLocked;
    case 'google_email_unverified':
      return l10n.errorGoogleEmailUnverified;
    // The one uniqueness rule left after email was decoupled from identity:
    // a Google account maps to at most one account here.
    case 'google_account_in_use':
    case 'google_account_mismatch':
      return l10n.errorGoogleAccountInUse;
    case 'google_already_linked':
      return l10n.errorGoogleAlreadyLinked;
    // Both are "not your fault, try again": an ID token that expired while the
    // user hesitated, and Google being unreachable from the backend.
    case 'google_invalid_id_token':
    case 'google_verification_unavailable':
      return l10n.errorGoogleSignInFailed;
    case 'google_oauth_disabled':
      return l10n.errorGoogleOauthDisabled;

    // ---- email verification --------------------------------------------------
    case 'unverified_user':
      return l10n.errorUnverifiedUser;
    case 'invalid_verification_code':
      final remaining = error.detail['attempts_remaining'];
      if (remaining is int) {
        return remaining > 0
            ? l10n.errorInvalidCodeRemaining(remaining)
            : l10n.errorInvalidCodeExhausted;
      }
      return l10n.errorInvalidCodeGeneric;
    case 'verification_code_expired':
      return l10n.errorVerificationCodeExpired;
    case 'too_many_verification_attempts':
      return l10n.errorTooManyVerificationAttempts;
    case 'resend_cooldown':
      final retryAfter = error.detail['retry_after'];
      return retryAfter is int
          ? l10n.errorResendCooldownWait(retryAfter)
          : l10n.errorResendCooldownGeneric;
    case 'email_send_failed':
      return l10n.errorEmailSendFailed;

    // ---- posting ------------------------------------------------------------
    case 'insufficient_tokens':
      final price = error.detail['price'] as int? ?? 0;
      final balance = error.detail['balance'] as int? ?? 0;
      return l10n.errorInsufficientTokens(price, balance);
    case 'channel_not_found':
      return l10n.errorChannelNotFound;

    // ---- reviewing ----------------------------------------------------------
    // Both mean the post left this user's queue while the card was still on
    // screen — stale UI rather than a real failure, so point at the fix.
    case 'not_in_queue':
      return l10n.errorNotInQueue;
    case 'already_reviewed':
      return l10n.errorAlreadyReviewed;
    case 'post_not_found':
      return l10n.errorPostNotFound;
    // Answered by `DELETE /posts/feed/{id}` when the post is in fact still
    // there — this client's list is stale, not the server's.
    case 'post_available':
      return l10n.errorPostAvailable;

    // ---- deleting an account ------------------------------------------------
    case 'delete_account_wrong_password':
      return l10n.errorDeleteAccountWrongPassword;
    case 'delete_account_password_required':
      return l10n.errorDeleteAccountPasswordRequired;

    // ---- pacing -------------------------------------------------------------
    // One budget covers posting, forwarding and dropping, so the copy has to work
    // for all three. `retry_after` is whole seconds, and never below 1.
    case 'rate_limited':
      final retryAfter = error.detail['retry_after'];
      return retryAfter is int
          ? l10n.errorRateLimitedWait(retryAfter)
          : l10n.errorRateLimitedGeneric;

    // ---- profile picture -----------------------------------------------------
    // Both are checked server-side (see `PROFILE_PICTURE_*` in the backend
    // config), because the picker can hand back anything the gallery holds.
    case 'profile_picture_invalid_type':
      return l10n.errorProfilePictureInvalidType;
    case 'profile_picture_too_large':
      return l10n.errorProfilePictureTooLarge;

    // ---- post media (images & videos) ----------------------------------------
    // All checked server-side (see POST_MEDIA_*/POST_IMAGE_*/POST_VIDEO_* in the
    // backend config) - the composer's own picker limits are only a courtesy.
    case 'post_media_too_many_files':
      return l10n.errorPostMediaTooManyFiles;
    case 'post_media_invalid_type':
      return l10n.errorPostMediaInvalidType;
    case 'post_media_too_large':
      return l10n.errorPostMediaTooLarge;
    case 'post_media_total_too_large':
      return l10n.errorPostMediaTotalTooLarge;
    case 'post_media_video_too_long':
      return l10n.errorPostMediaVideoTooLong;
    // Only reachable if a photo skipped the cropper: the backend fixes the two
    // allowed shapes and rejects anything else rather than cropping for you.
    case 'post_media_invalid_aspect_ratio':
      return l10n.errorPostMediaInvalidAspectRatio;
    case 'post_blocks_invalid':
      return l10n.errorPostBlocksInvalid;
    case 'post_blocks_empty':
      return l10n.errorPostBlocksEmpty;
    case 'post_blocks_too_many':
      return l10n.errorPostBlocksTooMany;

    // ---- feedback ------------------------------------------------------------
    // Its own family rather than a reuse of the post_media_* codes: the wording
    // has to make sense on a screen with no post on it, and the rules differ —
    // notably there is no `feedback_media_invalid_aspect_ratio`, because a
    // screenshot's shape is never wrong.
    case 'feedback_consent_required':
      return l10n.errorFeedbackConsentRequired;
    case 'feedback_message_empty':
      return l10n.errorFeedbackMessageEmpty;
    case 'feedback_message_too_long':
      return l10n.errorFeedbackMessageTooLong;
    case 'feedback_media_invalid_type':
      return l10n.errorFeedbackMediaInvalidType;
    case 'feedback_media_too_large':
      return l10n.errorFeedbackMediaTooLarge;
    case 'feedback_media_total_too_large':
      return l10n.errorFeedbackMediaTotalTooLarge;
    case 'feedback_media_too_many_files':
      return l10n.errorFeedbackMediaTooManyFiles;
    case 'feedback_media_video_too_long':
      return l10n.errorFeedbackMediaVideoTooLong;
    // Deliberately absent: `feedback_invalid_kind`, `feedback_invalid_rating`,
    // `feedback_rating_not_allowed` and `feedback_contact_requires_identity`.
    // All four mean the form and the backend disagree about what the form is —
    // a bug in this app, not something the person filling it in can act on — so
    // they fall through to the generic message rather than getting copy that
    // implies otherwise.

    // The bucket holding uploaded media was unreachable (see the backend's
    // `app/core/storage.py`). Worth its own copy rather than falling through to
    // the generic message: nothing about the file was wrong, so "try a different
    // photo" would send someone off fixing the one thing that is fine.
    case 'media_storage_unavailable':
      return l10n.errorMediaStorageUnavailable;

    // ---- generic ------------------------------------------------------------
    case 'unauthorized':
      return l10n.errorUnauthorized;
    case 'forbidden':
      return l10n.errorForbidden;
    case 'validation_error':
      final fields = error.detail['fields'];
      if (fields is List && fields.isNotEmpty) {
        final first = fields.first;
        if (first is Map && first['message'] != null) {
          return l10n.errorValidationWithDetail(first['message'] as String);
        }
      }
      return l10n.errorValidationGeneric;
    case 'internal_error':
      return l10n.errorInternalError;
    default:
      return l10n.errorUnknown;
  }
}

/// Maps the backend's `{code, params}` violation list (see
/// `backend/app/core/password_policy.py`) into one sentence. Tolerant of an
/// empty/unrecognized list (falls back to generic copy) and of a legacy plain
/// string `reason` (pre-i18n backend), so a version mismatch degrades rather
/// than crashing.
String _passwordErrorMessage(AppLocalizations l10n, Object? reason) {
  if (reason is String && reason.isNotEmpty) return reason;
  if (reason is List && reason.isNotEmpty) {
    final parts = reason
        .whereType<Map>()
        .map((v) => _violationMessage(l10n, v))
        .where((s) => s.isNotEmpty);
    if (parts.isNotEmpty) return parts.join(' ');
  }
  return l10n.errorInvalidPasswordGeneric;
}

String _violationMessage(AppLocalizations l10n, Map violation) {
  final params = violation['params'];
  final p = params is Map ? params : const {};
  switch (violation['code']) {
    case 'password_too_short':
      return l10n.passwordTooShort((p['min_length'] as num?)?.toInt() ?? 0);
    case 'password_missing_variety':
      return l10n.passwordMissingVariety(
        (p['required_categories'] as num?)?.toInt() ?? 0,
      );
    default:
      return '';
  }
}

/// Short label for a full-screen error state — pairs with [messageFor] as the body.
String titleFor(AppLocalizations l10n, Object? rawError) {
  final error = asRelayException(rawError);
  if (error.isConnectivityFailure) return l10n.errorTitleOffline;
  if (error.kind == ApiErrorKind.unauthorized) {
    return l10n.errorTitleSessionExpired;
  }
  return l10n.errorTitleGeneric;
}
