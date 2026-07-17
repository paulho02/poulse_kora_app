import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../stats/application/stats_providers.dart';
import '../application/profile_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Inert, local-only — no notification system exists yet. Explicitly out
  // of scope for this MVP; not persisted or backed by any real preference.
  bool _newPostsNotification = true;
  bool _weeklyDigestNotification = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(reviewGateStatusProvider.notifier).ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    final gateStatus = ref.watch(reviewGateStatusProvider);
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Algorithm'),
          ListTile(
            title: const Text('Review gate'),
            trailing: Text(gateStatus == null ? '—' : '${gateStatus.reviewGate} posts'),
          ),
          const ListTile(
            title: Text('Queue priority'),
            trailing: Text('Newest first'),
          ),
          const _SectionHeader('Notifications'),
          SwitchListTile(
            title: const Text('New posts to review'),
            value: _newPostsNotification,
            onChanged: (value) => setState(() => _newPostsNotification = value),
          ),
          SwitchListTile(
            title: const Text('Weekly stats digest'),
            value: _weeklyDigestNotification,
            onChanged: (value) => setState(() => _weeklyDigestNotification = value),
          ),
          const _SectionHeader('Account'),
          profileAsync.when(
            data: (profile) => Column(
              children: [
                ListTile(
                  title: const Text('Username'),
                  trailing: Text(profile.username ?? '—'),
                ),
                ListTile(
                  title: const Text('Email'),
                  trailing: Text(profile.email),
                ),
              ],
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 0.5),
      ),
    );
  }
}
