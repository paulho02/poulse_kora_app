import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/settings/app_settings.dart';
import '../data/profile_repository.dart';
import '../data/user_profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(
    ref.watch(dioClientProvider).dio,
    ref.watch(jsonCacheProvider),
  );
});

class ProfileNotifier extends AsyncNotifier<Cached<UserProfile>> {
  @override
  Future<Cached<UserProfile>> build() async {
    final profile = await ref.read(profileRepositoryProvider).fetchMe();
    if (!profile.isStale) {
      await _reconcileSettings(profile.data);
    }
    return profile;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }

  Future<void> updateBio(String bio) async {
    final current = state.value;
    if (current == null) return;
    final updated = await ref
        .read(profileRepositoryProvider)
        .updateMe(bio: bio);
    state = AsyncData(Cached.live(updated));
  }

  /// Flip dark mode. The local store is updated first and unconditionally, so
  /// the theme changes instantly whether or not the device is online.
  ///
  /// A failed push is *not* surfaced as an error and *not* rolled back — unlike
  /// every other write in the app. Settings are idempotent last-write-wins, so a
  /// pending change is simply sent on the next reconnect; nothing was lost and
  /// there is nothing for the user to act on.
  Future<void> setDarkMode(bool value) async {
    await ref.read(appSettingsProvider.notifier).setDarkMode(value);
    try {
      final updated = await ref
          .read(profileRepositoryProvider)
          .updateMe(darkMode: value);
      await ref
          .read(appSettingsProvider.notifier)
          .markPushed(updated.settingsRevision);
      state = AsyncData(Cached.live(updated));
    } catch (e) {
      final failure = asRelayException(e);
      if (!failure.isConnectivityFailure) rethrow;
    }
  }

  /// Set the account's username.
  ///
  /// Used by the onboarding username step, which Google signups get because the
  /// backend had to derive a name for them (Google supplies no username, and
  /// `UserCreate.username` is normally required). Rethrows like
  /// [completeOnboarding] rather than softening offline failures: there is a
  /// real value the user typed, and silently dropping it would be worse than
  /// telling them to retry.
  Future<void> updateUsername(String username) async {
    final updated = await ref
        .read(profileRepositoryProvider)
        .updateMe(username: username);
    state = AsyncData(Cached.live(updated));
  }

  /// Confirms the one-time post-registration onboarding flow. Unlike
  /// `setDarkMode`, this has no offline path: reaching this point already
  /// required the network (channel subscriptions in the flow's second step),
  /// so a failure here rethrows and the onboarding screen surfaces it as a
  /// retryable error rather than softening it.
  Future<void> completeOnboarding() async {
    final updated = await ref
        .read(profileRepositoryProvider)
        .updateMe(onboardingCompleted: true);
    state = AsyncData(Cached.live(updated));
  }

  /// Reconcile the device's local settings with the server's.
  ///
  /// The decision is driven by the local `dirty` flag, not by comparing
  /// timestamps: "did I change this since my last successful sync?" is a question
  /// the device can answer on its own, whereas "which value is newer?" would need
  /// the device and server clocks to agree.
  ///
  ///   !dirty                      -> pull; the server is authoritative.
  ///   dirty, revisions match      -> push; nobody else touched it, safe.
  ///   dirty, server ahead         -> conflict; local wins (see below).
  ///
  /// Local-wins on conflict is deliberate. For a single-user preference,
  /// reverting a toggle the user just flipped on *this* device is a more
  /// surprising failure than losing a change they made on another one.
  Future<void> _reconcileSettings(UserProfile serverProfile) async {
    final settings = ref.read(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    final action = decideSettingsSync(
      local: settings,
      serverDarkMode: serverProfile.darkMode,
      serverRevision: serverProfile.settingsRevision,
    );

    switch (action) {
      case SettingsSyncAction.pull:
        await notifier.adoptFromServer(
          darkMode: serverProfile.darkMode,
          revision: serverProfile.settingsRevision,
        );
      case SettingsSyncAction.alreadyInSync:
        // Nothing to send; just stop treating it as pending.
        await notifier.markPushed(serverProfile.settingsRevision);
      case SettingsSyncAction.push:
        try {
          final updated = await ref
              .read(profileRepositoryProvider)
              .updateMe(darkMode: settings.darkMode);
          await notifier.markPushed(updated.settingsRevision);
        } catch (e) {
          // Still offline, or the push failed. Stay dirty and retry on the next
          // reconnect — the local value keeps rendering in the meantime.
          if (!asRelayException(e).isConnectivityFailure) rethrow;
        }
    }
  }

  /// Called when connectivity is restored: re-fetch and settle any pending
  /// local settings change.
  Future<void> syncAfterReconnect() async {
    try {
      final profile = await ref.read(profileRepositoryProvider).fetchMe();
      if (profile.isStale) return;
      await _reconcileSettings(profile.data);
      state = AsyncData(profile);
    } on RelayApiException catch (_) {
      // Best-effort; the banner already tells the user what's going on.
    }
  }
}

final profileProvider =
    AsyncNotifierProvider<ProfileNotifier, Cached<UserProfile>>(
      ProfileNotifier.new,
    );
