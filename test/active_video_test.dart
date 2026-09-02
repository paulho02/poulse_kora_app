import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/src/core/media/application/active_video.dart';

/// The rule `InlineMediaBlock` leans on: at most one clip is claimed at a time,
/// and a block that has already lost the claim cannot revoke the newer one on
/// its way out — a stale release would leave nothing marked as playing while a
/// clip is in fact running, and the next block to start would not stop it.
void main() {
  late ProviderContainer container;
  late ActiveVideoNotifier active;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    active = container.read(activeVideoProvider.notifier);
  });

  test('nothing is playing to begin with', () {
    expect(container.read(activeVideoProvider), isNull);
  });

  test('a claim replaces the previous one', () {
    final first = Object();
    final second = Object();

    active.claim(first);
    expect(container.read(activeVideoProvider), same(first));

    active.claim(second);
    expect(container.read(activeVideoProvider), same(second));
  });

  test('releasing the held claim clears it', () {
    final token = Object();
    active.claim(token);
    active.release(token);
    expect(container.read(activeVideoProvider), isNull);
  });

  test('releasing a claim someone else has taken over leaves theirs alone', () {
    final displaced = Object();
    final current = Object();

    active.claim(displaced);
    active.claim(current);
    // The displaced block pauses, and its pause listener releases *its* token.
    active.release(displaced);

    expect(container.read(activeVideoProvider), same(current));
  });
}
