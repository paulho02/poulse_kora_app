import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/language_picker.dart';
import '../../../core/settings/locale_settings.dart';
import '../../../core/tips/application/tip_providers.dart';
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
    Future.microtask(
      () => ref.read(reviewGateStatusProvider.notifier).ensureLoaded(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gateStatus = ref.watch(reviewGateStatusProvider);
    final profileAsync = ref.watch(profileProvider);
    final l10n = AppLocalizations.of(context);
    final localeOverride = ref.watch(localeOverrideProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          _SectionHeader(l10n.settingsSectionAlgorithm),
          ListTile(
            title: Text(l10n.settingsReviewGate),
            trailing: Text(
              gateStatus == null
                  ? '—'
                  : l10n.settingsReviewGatePosts(gateStatus.reviewGate),
            ),
          ),
          ListTile(
            title: Text(l10n.settingsQueuePriority),
            trailing: Text(l10n.settingsQueuePriorityValue),
          ),
          _SectionHeader(l10n.settingsLanguageSectionHeader),
          ListTile(
            title: Text(l10n.settingsLanguageSectionHeader),
            trailing: Text(localeLabel(l10n, localeOverride)),
            onTap: () => pickLanguage(context, ref),
          ),
          _SectionHeader(l10n.settingsSectionNotifications),
          SwitchListTile(
            title: Text(l10n.settingsNewPostsNotification),
            value: _newPostsNotification,
            onChanged: (value) => setState(() => _newPostsNotification = value),
          ),
          SwitchListTile(
            title: Text(l10n.settingsWeeklyDigestNotification),
            value: _weeklyDigestNotification,
            onChanged: (value) =>
                setState(() => _weeklyDigestNotification = value),
          ),
          _SectionHeader(l10n.settingsSectionHelp),
          ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: Text(l10n.settingsResetTutorialHints),
            subtitle: Text(l10n.settingsResetTutorialHintsSubtitle),
            onTap: () {
              resetAllTips(ref);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(l10n.settingsResetTutorialHintsSnackbar),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            },
          ),
          ListTile(
            leading: const Icon(Icons.slideshow_outlined),
            title: Text(l10n.settingsReplayIntro),
            subtitle: Text(l10n.settingsReplayIntroSubtitle),
            onTap: () => context.push('/onboarding/replay'),
          ),
          _SectionHeader(l10n.settingsSectionAccount),
          profileAsync.when(
            data: (profile) => Column(
              children: [
                ListTile(
                  title: Text(l10n.commonUsername),
                  trailing: Text(profile.data.username ?? '—'),
                ),
                ListTile(
                  title: Text(l10n.commonEmail),
                  trailing: Text(profile.data.email),
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
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(letterSpacing: 0.5),
      ),
    );
  }
}
