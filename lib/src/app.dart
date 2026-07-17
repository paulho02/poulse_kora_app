import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_providers.dart';
import 'features/profile/application/profile_providers.dart';
import 'routing/app_router.dart';

class PoulseKoraApp extends ConsumerWidget {
  const PoulseKoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Avoid a flash of the login screen while the stored token is still
    // being read from secure storage on cold start.
    final authState = ref.watch(authNotifierProvider);
    if (authState.isLoading) {
      return MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final router = ref.watch(routerProvider);

    // Only read the profile's synced dark-mode preference once logged in —
    // fetching it while unauthenticated would just 401.
    final loggedIn = authState.value ?? false;
    final themeMode = loggedIn
        ? ref.watch(profileProvider).maybeWhen(
              data: (profile) => profile.darkMode ? ThemeMode.dark : ThemeMode.light,
              orElse: () => ThemeMode.system,
            )
        : ThemeMode.system;

    return MaterialApp.router(
      title: 'Relay',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
