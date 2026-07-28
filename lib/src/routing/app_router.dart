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

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);
  final loggedIn = authState.value ?? false;

  // Only watched once logged in: `profileProvider` hits `/users/me`, which
  // 401s pre-login, and there is no reason to pay for that fetch (or its
  // retry/error handling) while sitting on the login screen.
  //
  // `null` covers "still loading" and "failed to load" alike, and both are
  // treated as "don't force onboarding"/"don't force verification" below —
  // fail open, since blocking an existing user's feed over a transient
  // profile fetch failure is worse than occasionally not re-showing one of
  // these one-time screens.
  final profile = loggedIn ? ref.watch(profileProvider).value?.data : null;
  final onboardingCompleted = profile?.onboardingCompleted;

  // Only actually gates navigation when the backend currently enforces it -
  // `is_verified` can legitimately stay false forever with the flag off, so
  // this must not force the verify screen in that case. Also fails open
  // (treats as "not required") if the public config hasn't loaded yet.
  final requireEmailVerification =
      ref.watch(appConfigProvider).value?.requireEmailVerification ?? false;
  final needsEmailVerification =
      requireEmailVerification && profile?.isVerified == false;

  return GoRouter(
    initialLocation: '/feed',
    redirect: (context, state) {
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
