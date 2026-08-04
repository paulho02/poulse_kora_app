import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/tips/presentation/view_tip.dart';
import '../../auth/application/auth_providers.dart';
import '../../stats/application/stats_providers.dart';
import '../application/profile_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final statsAsync = ref.watch(statsProvider);
    // Read the toggle from the local store, not the server profile — that's what
    // keeps it correct and usable with no connection.
    final darkMode = ref.watch(appSettingsProvider).darkMode;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/profile/settings'),
          ),
        ],
      ),
      body: ViewTip(
        tipKey: 'tip.profile',
        message: l10n.profileTipMessage,
        child: profileAsync.when(
          data: (cached) {
            final profile = cached.data;
            final username = profile.username ?? profile.email;
            final avatarColor = AppColors.avatarColor(username);
            return RefreshIndicator(
              onRefresh: () => ref.read(profileProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (cached.staleLabel != null) ...[
                    StaleDataNotice(label: cached.staleLabel!),
                    const SizedBox(height: 12),
                  ],
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: avatarColor,
                          child: Text(
                            username.isNotEmpty
                                ? username[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 28,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(username, style: theme.textTheme.titleLarge),
                        if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            profile.bio!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  statsAsync.when(
                    data: (stats) => Row(
                      children: [
                        _StatTile(
                          label: l10n.profileStatCreated,
                          value: stats.data.createdPostCount,
                          onTap: () => context.push('/profile/posted'),
                        ),
                        _StatTile(
                          label: l10n.statsReviewed,
                          value: stats.data.reviewedCount,
                          onTap: () => context.push('/profile/reviewed'),
                        ),
                        _StatTile(
                          label: l10n.profileStatTrust,
                          value: stats.data.trustScore,
                        ),
                      ],
                    ),
                    loading: () => const SizedBox(
                      height: 80,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: SwitchListTile(
                      title: Text(l10n.profileDarkMode),
                      secondary: const Icon(Icons.dark_mode_outlined),
                      value: darkMode,
                      // No try/catch and no error message on purpose: the theme has
                      // already changed locally, and a push that fails offline is
                      // retried on reconnect. There's nothing for the user to do.
                      onChanged: (value) =>
                          ref.read(profileProvider.notifier).setDarkMode(value),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () =>
                        ref.read(authNotifierProvider.notifier).logout(),
                    child: Text(l10n.profileSignOut),
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorStateView(
            error: error,
            onRetry: () => ref.invalidate(profileProvider),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.onTap});

  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Text('$value', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: theme.textTheme.labelSmall),
                    // Matches the "tap for details" chevron in beta_banner.dart —
                    // only shown when the tile is actually tappable, so the
                    // non-interactive Trust tile doesn't look clickable too.
                    if (onTap != null) ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
