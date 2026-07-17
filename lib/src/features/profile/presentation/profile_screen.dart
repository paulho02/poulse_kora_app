import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_providers.dart';
import '../../stats/application/stats_providers.dart';
import '../application/profile_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final statsAsync = ref.watch(statsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/profile/settings'),
          ),
        ],
      ),
      body: profileAsync.when(
        data: (profile) {
          final username = profile.username ?? profile.email;
          final avatarColor = AppColors.avatarColor(username);
          return RefreshIndicator(
            onRefresh: () => ref.read(profileProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: avatarColor,
                        child: Text(
                          username.isNotEmpty ? username[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
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
                      _StatTile(label: 'Created', value: stats.createdPostCount),
                      _StatTile(label: 'Reviewed', value: stats.reviewedCount),
                      _StatTile(label: 'Trust', value: stats.trustScore),
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
                    title: const Text('Dark Mode'),
                    secondary: const Icon(Icons.dark_mode_outlined),
                    value: profile.darkMode,
                    onChanged: (_) async {
                      try {
                        await ref.read(profileProvider.notifier).toggleDarkMode();
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not update dark mode')),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load profile:\n$error')),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text('$value', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(label, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
