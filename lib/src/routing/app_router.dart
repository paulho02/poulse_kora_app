import 'package:flutter/widgets.dart';
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
import '../features/feedback/presentation/feedback_screen.dart';
import '../features/history/presentation/post_history_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/profile/application/profile_providers.dart';
import '../features/profile/presentation/change_password_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/profile/presentation/settings_screen.dart';
import '../features/stats/presentation/stats_screen.dart';
import '../features/tutorial/presentation/tutorial_deck.dart';
import 'app_shell.dart';

const _authRoutes = {'/login', '/register'};
const _verifyEmailRoute = '/verify-email';
const _onboardingRoute = '/onboarding';

/// Deliberately outside every gate below — see the early return in `redirect`.
const _feedbackRoute = '/feedback';

/// The context `MaterialApp.router`'s `builder` receives (and thus
/// [BetaBanner]/[OfflineBanner]/[InfoBanner], which wrap the routed content
/// there) sits *above* this Navigator in the tree, not below it — so
/// `Navigator.of(context)` from that context never finds it, no matter how
/// deep the widget that calls it. Anything outside the routed tree that
/// needs to push a route or open a sheet/dialog over it must go through
/// this key's `currentContext` instead.
final rootNavigatorKey = GlobalKey<NavigatorState>();

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

      if (isLoggedIn) _attachProfileListener(ref);
    });
    ref.listen(appConfigProvider, (previous, next) {
      final prevRequire = previous?.value?.requireEmailVerification;
      final nextRequire = next.value?.requireEmailVerification;
      if (prevRequire != nextRequire) notifyListeners();
    });
    // A live `unverified_user` 403 is authoritative over whatever
    // `appConfigProvider` cached at app start (see that provider's doc) - e.g.
    // `REQUIRE_EMAIL_VERIFICATION` flipped on mid-session. Always a
    // false->true transition since the notifier only ever sets it once, so no
    // need to compare previous/next.
    ref.listen(serverConfirmedVerificationRequiredProvider, (previous, next) {
      notifyListeners();
    });

    // `routerProvider` (and thus this notifier) is only built once
    // `authReadyProvider` resolves (see `app.dart`), which is itself gated on
    // `authNotifierProvider` finishing its cold-start token read. So on a
    // cold start with an existing stored token, `authNotifierProvider` is
    // *already* `AsyncData(true)` by the time the `ref.listen` above is
    // attached — there is no future logged-out -> logged-in transition left
    // to observe, so that callback would never fire and the profile listener
    // below would never attach. Without it, `redirect` never learns that
    // `profileProvider` resolved (e.g. to `isVerified: false`), so an
    // existing unverified user reopening the app stays on `/feed` and hits
    // the raw `unverified_user` error from every request instead of being
    // routed to `/verify-email`. Covering that here, once, at construction
    // time closes the gap; the listener inside the callback above still
    // covers a live login/registration happening after this notifier exists.
    if (ref.read(authNotifierProvider).value ?? false) {
      _attachProfileListener(ref);
    }
  }

  var _profileListenerAttached = false;

  // `profileProvider` must not be subscribed to before there is a token —
  // merely listening to an `AsyncNotifierProvider` runs its `build()`, which
  // calls `GET /users/me` unconditionally. Only ever called once logged in,
  // and only once total, since re-attaching would otherwise double-fire
  // whenever this runs from both the constructor's upfront check and a
  // subsequent auth transition.
  void _attachProfileListener(Ref ref) {
    if (_profileListenerAttached) return;
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
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/feed',
    refreshListenable: refresh,
    redirect: (context, state) {
      // Reachable in every state: signed out, unverified, mid-onboarding. The
      // reports most worth receiving are exactly the ones from people the gates
      // below have stopped ("I can't sign in", "the code never arrives"), and
      // those are unreportable from anywhere else in the app. The backend allows
      // this route without a token for the same reason.
      if (state.matchedLocation == _feedbackRoute) return null;

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
      // loaded yet. ORed with `serverConfirmedVerificationRequiredProvider`
      // so a stale cached `false` (e.g. the flag was turned on after this
      // config fetch) can't mask an actual `unverified_user` rejection the
      // user just hit.
      final requireEmailVerification =
          (ref.read(appConfigProvider).value?.requireEmailVerification ??
              false) ||
          ref.read(serverConfirmedVerificationRequiredProvider);
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
        path: _feedbackRoute,
        name: 'feedback',
        builder: (context, state) => const FeedbackScreen(),
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
      // A normal pushed route (unlike `_onboardingRoute`, which the redirect
      // above owns) — reached from Settings' "Replay intro" for an
      // already-onboarded user, see `OnboardingScreen.isReplay`. Distinct
      // from `_onboardingRoute` so the redirect's "already onboarded, bounce
      // to /feed" check (keyed on `_onboardingRoute` exactly) leaves it alone.
      GoRoute(
        path: '/onboarding/replay',
        name: 'onboardingReplay',
        builder: (context, state) => const OnboardingScreen(isReplay: true),
      ),
      // "How Relay works", from Settings. Needs no exemption from the gate
      // chain above: it is only ever pushed by an account that is signed in,
      // verified and onboarded, so every check has already passed by the time
      // it can be reached. Onboarding shows the same deck as an embedded step
      // instead of pushing this - see `OnboardingScreen`.
      GoRoute(
        path: '/tutorial',
        name: 'tutorial',
        builder: (context, state) => const TutorialScreen(),
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
                    routes: [
                      GoRoute(
                        path: 'change-password',
                        name: 'changePassword',
                        builder: (context, state) =>
                            const ChangePasswordScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'posted',
                    name: 'profile-posted',
                    builder: (context, state) =>
                        const PostHistoryScreen(mode: HistoryMode.posted),
                  ),
                  GoRoute(
                    path: 'reviewed',
                    name: 'profile-reviewed',
                    builder: (context, state) =>
                        const PostHistoryScreen(mode: HistoryMode.reviewed),
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
