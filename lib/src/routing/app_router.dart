import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_providers.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/channels/presentation/channels_screen.dart';
import '../features/create_post/presentation/create_post_screen.dart';
import '../features/feed/presentation/feed_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/profile/presentation/settings_screen.dart';
import '../features/stats/presentation/stats_screen.dart';
import 'app_shell.dart';

const _authRoutes = {'/login', '/register'};

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);
  final loggedIn = authState.value ?? false;

  return GoRouter(
    initialLocation: '/feed',
    redirect: (context, state) {
      final onAuthRoute = _authRoutes.contains(state.matchedLocation);
      if (!loggedIn && !onAuthRoute) return '/login';
      if (loggedIn && onAuthRoute) return '/feed';
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
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/feed', name: 'feed', builder: (context, state) => const FeedScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/channels',
              name: 'channels',
              builder: (context, state) => const ChannelsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/create',
              name: 'create',
              builder: (context, state) => const CreatePostScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/stats',
              name: 'stats',
              builder: (context, state) => const StatsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
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
          ]),
        ],
      ),
    ],
  );
});
