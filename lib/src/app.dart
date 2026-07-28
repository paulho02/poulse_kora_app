import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/announcements/application/announcement_providers.dart';
import 'core/announcements/presentation/info_banner.dart';
import 'core/app_config/application/app_config_providers.dart';
import 'core/network/connectivity.dart';
import 'core/presentation/offline_banner.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_providers.dart';
import 'features/channels/application/channels_providers.dart';
import 'features/economy/application/economy_providers.dart';
import 'features/email_verification/application/email_verification_providers.dart';
import 'features/feed/application/feed_providers.dart';
import 'features/profile/application/profile_providers.dart';
import 'features/stats/application/stats_providers.dart';
import 'routing/app_router.dart';

class PoulseKoraApp extends ConsumerWidget {
  const PoulseKoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The theme comes from the *local* settings store, never from the server
    // profile. Reading it from the network meant a preference the app already
    // knew about was unavailable whenever the backend was.
    final themeMode = ref.watch(appSettingsProvider).themeMode;

    // Public endpoint, checked pre-login too — warm it here rather than
    // waiting for InfoBanner to mount, since the splash-screen return below
    // has no builder and would otherwise delay the fetch until it clears.
    //
    // `listen`, not `watch`: this widget is the app root, so a `watch` here
    // would rebuild the entire `MaterialApp.router` — and therefore every
    // currently-mounted route — the instant the fetch resolves. That collided
    // with whatever screen happened to be mid-build at that moment (observed:
    // "setState() or markNeedsBuild() called during build" from FeedScreen).
    // `InfoBanner` already does its own narrowly-scoped watch for the actual
    // value; this call exists purely to start the fetch early.
    ref.listen(announcementProvider, (previous, next) {});
    // Same reasoning: the router's redirect needs `requireEmailVerification`
    // before it can decide whether to show `/verify-email`, so start the fetch
    // now rather than waiting for the router to first `watch` it.
    ref.listen(appConfigProvider, (previous, next) {});

    // Session boundaries. Logging out clears the token, the response cache and
    // local settings, but the providers holding already-fetched data are
    // keep-alive and survive it — so without this, signing in as a different
    // account on the same device would show the previous user's feed, profile and
    // counters until each happened to refetch.
    //
    // Invalidating on the way out also makes the warm below work: `ref.read` on a
    // provider that still holds state is a no-op and would never re-run the pull.
    ref.listen<AsyncValue<bool>>(authNotifierProvider, (previous, next) {
      final was = previous?.value ?? false;
      final now = next.value;

      if (was && now == false) {
        ref.invalidate(profileProvider);
        ref.invalidate(emailVerificationProvider);
        ref.invalidate(feedNotifierProvider);
        ref.invalidate(channelsNotifierProvider);
        ref.invalidate(selectedChannelFilterProvider);
        ref.invalidate(economyProvider);
        ref.invalidate(reviewGateStatusProvider);
        ref.invalidate(statsProvider);
        ref.invalidate(globalStatsProvider);
        return;
      }

      // Signing in wipes local settings so the previous account's theme can't
      // carry over, leaving this device on the defaults until something pulls the
      // new account's preferences. `profileProvider` is what pulls them, but it's
      // lazy — nothing builds it until the Profile tab is opened. Warm it here, or
      // signing in shows light mode until you go looking for the setting.
      if (!was && now == true) {
        ref.read(profileProvider.future).ignore();
      }
    });

    // Recover once we're back: settle any preference changed while offline, and
    // rebuild whatever failed outright.
    ref.listen<ConnectionStatus>(connectivityProvider, (previous, next) {
      if (previous != ConnectionStatus.offline ||
          next != ConnectionStatus.backOnline) {
        return;
      }
      ref.read(profileProvider.notifier).syncAfterReconnect();
      ref.read(economyProvider.notifier).refresh();

      // Only invalidate providers sitting on an error — those have nothing worth
      // keeping. Blanket-invalidating would also throw away a perfectly readable
      // cached feed and yank the list out from under someone mid-scroll.
      if (ref.read(feedNotifierProvider).hasError) {
        ref.invalidate(feedNotifierProvider);
      }
      if (ref.read(channelsNotifierProvider).hasError) {
        ref.invalidate(channelsNotifierProvider);
      }
      if (ref.read(statsProvider).hasError) ref.invalidate(statsProvider);
      if (ref.read(globalStatsProvider).hasError) {
        ref.invalidate(globalStatsProvider);
      }
    });

    // Avoid a flash of the login screen while the stored token is still
    // being read from secure storage on cold start.
    final authState = ref.watch(authNotifierProvider);
    if (authState.isLoading) {
      return MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Relay',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      // Wrapping here rather than in AppShell puts the banners over every
      // route, including login/register, which sit outside the shell.
      // Connectivity state is the more urgent/certain of the two, so it
      // renders above the announcement.
      builder: (context, child) => OfflineBanner(
        child: InfoBanner(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
