import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one clip allowed to be playing, app-wide — held as an opaque token
/// created by whichever block is playing (`InlineMediaBlock`), so nothing here
/// needs to know about media ids, controllers or widgets.
///
/// This exists because two players running at once is not just untidy, it is
/// where the playback bugs came from: a post with several clips would leave the
/// first one streaming (heard, not seen) under the second, and two concurrent
/// authenticated video streams competing for Android's decoders is what made
/// the second clip sit on a spinner forever. Starting a clip claims the token;
/// every other block sees the change and pauses itself.
class ActiveVideoNotifier extends Notifier<Object?> {
  @override
  Object? build() => null;

  void claim(Object token) => state = token;

  /// Only clears the claim if [token] still holds it — a block that was paused
  /// by someone else's claim must not wipe that newer claim on its way out.
  void release(Object token) {
    if (state == token) state = null;
  }
}

final activeVideoProvider = NotifierProvider<ActiveVideoNotifier, Object?>(
  ActiveVideoNotifier.new,
);
