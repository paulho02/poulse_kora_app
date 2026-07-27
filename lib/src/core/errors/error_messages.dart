import 'api_exception.dart';

/// Single place where a failure becomes something a person can read.
///
/// Keyed on the backend's machine-readable `detail.error` code (see
/// `backend/app/core/errors.py`), so adding a new server-side error means adding
/// one case here rather than hunting through screens. Never render an exception's
/// `toString()` at a call site — that is what produced the raw Dio dumps this
/// replaces.
String messageFor(Object? rawError) {
  // Unwrap first: `AsyncValue.guard` hands widgets the raw `DioException` that
  // Dio rethrows, not the normalized failure inside it.
  final error = asRelayException(rawError);

  switch (error.error) {
    // ---- connectivity -------------------------------------------------------
    case 'offline':
      return "You're offline. This needs a connection — try again once you're back.";
    case 'timeout':
      return 'The server took too long to respond. Check your connection and try again.';

    // ---- posting ------------------------------------------------------------
    case 'insufficient_tokens':
      final price = error.detail['price'];
      final balance = error.detail['balance'];
      return 'Not enough tokens to post (need $price, you have $balance). '
          'Review posts in your feed to earn more.';
    case 'channel_not_found':
      return "That channel doesn't exist anymore. Pick another one.";

    // ---- reviewing ----------------------------------------------------------
    // Both mean the post left this user's queue while the card was still on
    // screen — stale UI rather than a real failure, so point at the fix.
    case 'not_in_queue':
      return 'That post is no longer in your queue. Pull down to refresh your feed.';
    case 'already_reviewed':
      return "You've already reviewed that post. Pull down to refresh your feed.";
    case 'post_not_found':
      return 'That post is no longer available.';

    // ---- generic ------------------------------------------------------------
    case 'unauthorized':
      return 'Your session has expired. Please sign in again.';
    case 'validation_error':
      final fields = error.detail['fields'];
      if (fields is List && fields.isNotEmpty) {
        final first = fields.first;
        if (first is Map && first['message'] != null) {
          return 'Check your input: ${first['message']}';
        }
      }
      return "That didn't look right. Check your input and try again.";
    case 'internal_error':
      return 'Something went wrong on our end. Please try again in a moment.';
    default:
      return 'Something went wrong. Please try again.';
  }
}

/// Short label for a full-screen error state — pairs with [messageFor] as the body.
String titleFor(Object? rawError) {
  final error = asRelayException(rawError);
  if (error.isConnectivityFailure) return "You're offline";
  if (error.kind == ApiErrorKind.unauthorized) return 'Session expired';
  return "Couldn't load this";
}
