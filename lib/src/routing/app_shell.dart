import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../features/feed/presentation/feed_waiting_icon.dart';

/// Bottom-nav shell for the 5 main tabs (Feed/Filters/Create/Stats/Profile),
/// wrapping a [StatefulShellRoute.indexedStack] so each tab keeps its own
/// navigation stack (e.g. Profile > Settings survives switching tabs).
///
/// "Filters" is `FeedPreferencesScreen` — channels and content languages,
/// the two things that decide what the feed delivers. It reuses
/// `l10n.feedPrefsTitle` for the label rather than a separate nav-only
/// string, matching every other tab here: the nav label and the screen's own
/// `AppBar` title are always the same word (see `feed_screen.dart`).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          NavigationDestination(
            // Carries the count of posts waiting to be read — see
            // [FeedWaitingIcon] for why that belongs here and not in the feed's
            // own app bar.
            icon: FeedWaitingIcon(selected: navigationShell.currentIndex == 0),
            selectedIcon: const Icon(Icons.forum),
            label: l10n.feedTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.filter_alt_outlined),
            selectedIcon: const Icon(Icons.filter_alt),
            label: l10n.feedPrefsTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.add_circle_outline),
            selectedIcon: const Icon(Icons.add_circle),
            label: l10n.navCreate,
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart),
            label: l10n.navStats,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.profileTitle,
          ),
        ],
      ),
    );
  }
}
