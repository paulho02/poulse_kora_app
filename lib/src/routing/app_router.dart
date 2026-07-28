import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_config/application/app_config_providers.dart';
import '../features/auth/application/auth_providers.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/channels/presentation/channels_screen.dart';
import '../features/create_post/presentation/create_post_screen.dart';
import '../features/email_verification/presentation/email_verification_screen.dart';
import '../features/feed/presentation/feed_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/profile/application/profile_providers.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/profile/presentation/settings_screen.dart';
import '../features/stats/presentation/stats_screen.dart';
import 'app_shell.dart';

const _authRoutes = {'/login', '/register'};
const _verifyEmailRoute = '/verify-email';
const _onboardingRoute = '/onboarding';

/// Bridges Riverpod state changes to go_router's `refreshListenable`, so the
/// router re-evaluates `redirect` without rebuilding the `GoRouter` itself.
///
/// `routerProvider` used to `ref.watch` these providers directly and return a
/// brand-new `GoRouter(...)` on every change. Swapping `MaterialApp.router`'s
/// `routerConfig` tears down and remounts the whole route tree — so a failed
/// login (state goes loading, then error) silently blew away `LoginScreen`'s
/// `State` mid-attempt: typed text lost, and the `ref.listen` that shows the
/// error snackbar got torn down before — or remounted after — the transition
/// it was meant to catch, so the error surfaced late, on whatever screen
/// happened to be current by the time it did. `GoRouter` is built exactly
/// once here instead; only `redirect` re-runs on each notification.
///
/// That alone isn't enough, though: `refreshListenable` firing at all makes
/// go_router re-evaluate its current `Page` for the active location, and even
/// with a stable `GoRouter`, that was *still* enough to reset `LoginScreen`'s
/// `State` (lost text, lost in-place error) on a failed login — because a
/// failed login is a `loading -> error` transition that never actually
/// changes `loggedIn`. There is nothing for `redirect` to reconsider in that
/// case, so each `notifyListeners()` call below is gated on the *derived,
/// redirect-relevant* value actually changing, not on the provider merely
/// emitting a new `AsyncValue`.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authNotifierProvider, (previous, next) {
      final wasLoggedIn = previous?.value ?? false;
      final isLoggedIn = next.value ?? false;
      if (wasLoggedIn != isLoggedIn) notifyListeners();

      // `profileProvider` must not be subscribed to before there is a token —
      // merely listening to an `AsyncNotifierProvider` runs its `build()`,
      // which calls `GET /users/me` unconditionally. Attaching this listener
      // eagerly in the constructor (instead of gating it on `loggedIn`) was
      // firing that fetch — and its guaranteed 401 — on every cold start,
      // before the user had even reached the login screen.
      if (isLoggedIn && !_profileListenerAttached) {
        _profileListenerAttached = true;
        ref.listen(profileProvider, (previous, next) {
          final prevData = previous?.value?.data;
          final nextData = next.value?.data;
          final relevantChange =
              prevData?.isVerified != nextData?.isVerified ||
              prevData?.onboardingCompleted != nextData?.onboardingCompleted;
          if (relevantChange) notifyListeners();
        });
      }
    });
    ref.listen(appConfigProvider, (previous, next) {
      final prevRequire = previous?.value?.requireEmailVerification;
      final nextRequire = next.value?.requireEmailVerification;
      if (prevRequire != nextRequire) notifyListeners();
    });
  }

  var _profileListenerAttached = false;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/feed',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(authNotifierProvider).value ?? false;

      // Only read once logged in: `profileProvider` hits `/users/me`, which
      // 401s pre-login, and there is no reason to pay for that fetch (or its
      // retry/error handling) while sitting on the login screen.
      //
      // `null` covers "still loading" and "failed to load" alike, and both
      // are treated as "don't force onboarding"/"don't force verification"
      // below — fail open, since blocking an existing user's feed over a
      // transient profile fetch failure is worse than occasionally not
      // re-showing one of these one-time screens.
      final profile = loggedIn ? ref.read(profileProvider).value?.data : null;
      final onboardingCompleted = profile?.onboardingCompleted;

      // Only actually gates navigation when the backend currently enforces it
      // - `is_verified` can legitimately stay false forever with the flag
      // off, so this must not force the verify screen in that case. Also
      // fails open (treats as "not required") if the public config hasn't
      // loaded yet.
      final requireEmailVerification =
          ref.read(appConfigProvider).value?.requireEmailVerification ??
          false;
      final needsEmailVerification =
          requireEmailVerification && profile?.isVerified == false;

      final onAuthRoute = _authRoutes.contains(state.matchedLocation);
      if (!loggedIn) return onAuthRoute ? null : '/login';
      if (onAuthRoute) return '/feed';

      // Must fully resolve (return null or bounce back here) before the
      // onboarding check below ever runs — otherwise an unverified account
      // with onboarding also incomplete alternates between the two routes
      // forever, since each thinks the other's route needs correcting.
      final onVerifyEmailRoute = state.matchedLocation == _verifyEmailRoute;
      if (needsEmailVerification) {
        return onVerifyEmailRoute ? null : _verifyEmailRoute;
      }
      if (onVerifyEmailRoute) return '/feed';

      final onOnboardingRoute = state.matchedLocation == _onboardingRoute;
      if (onboardingCompleted == false && !onOnboardingRoute) {
        return _onboardingRoute;
      }
      if (onboardingCompleted != false && onOnboardingRoute) return '/feed';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: _verifyEmailRoute,
        name: 'verifyEmail',
        builder: (context, state) => const EmailVerificationScreen(),
      ),
      GoRoute(
        path: _onboardingRoute,
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/feed',
                name: 'feed',
                builder: (context, state) => const FeedScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/channels',
                name: 'channels',
                builder: (context, state) => const ChannelsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/create',
                name: 'create',
                builder: (context, state) => const CreatePostScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stats',
                name: 'stats',
                builder: (context, state) => const StatsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: 'profile',
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'settings',
                    name: 'settings',
                    builder: (context, state) => const SettingsScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
