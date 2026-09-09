import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/language_picker.dart';
import '../../../core/settings/locale_settings.dart';
import '../../../core/tips/application/tip_providers.dart';
import '../../stats/application/stats_providers.dart';
import '../application/profile_providers.dart';
import 'delete_account_dialog.dart';
import 'google_link_tile.dart';

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
    final theme = Theme.of(context);
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
            leading: const Icon(Icons.hub_outlined),
            title: Text(l10n.settingsHowRelayWorks),
            subtitle: Text(l10n.settingsHowRelayWorksSubtitle),
            onTap: () => context.push('/tutorial'),
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
                  // Only spelled out when the Google row below shows a
                  // *different* address — otherwise the two rows look like they
                  // contradict each other. When they match, the distinction is
                  // academic and the extra line is noise.
                  subtitle: profile.data.hasDistinctGoogleEmail
                      ? Text(l10n.settingsEmailContactOnly)
                      : null,
                  trailing: Text(profile.data.email),
                ),
                // A Google account has no password to change — the backend
                // refuses `POST /auth/change-password` outright — so the row
                // would only ever lead to an error message.
                if (!profile.data.isGoogleAccount)
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(l10n.settingsChangePassword),
                    subtitle: Text(l10n.settingsChangePasswordSubtitle),
                    onTap: () =>
                        context.push('/profile/settings/change-password'),
                  ),
                GoogleLinkTile(profile: profile.data),
                const Divider(height: 32, indent: 16, endIndent: 16),
                // Last row on the screen, and the only one drawn in the error
                // colour: a destructive action should look like one before it
                // is tapped, not only once its dialog is open. No section
                // header of its own — a "Danger zone" heading would give it
                // more prominence than a setting nobody is looking for
                // deserves.
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    l10n.settingsDeleteAccount,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: Text(l10n.settingsDeleteAccountSubtitle),
                  onTap: () => showDeleteAccountDialog(context, profile.data),
                ),
              ],
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            // Falls back to the change-password row alone: without a profile we
            // can't know the account type, and hiding the only password
            // affordance on a transient fetch failure would be worse than
            // showing a row that answers with a clear error if tapped.
            error: (_, _) => ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(l10n.settingsChangePassword),
              subtitle: Text(l10n.settingsChangePasswordSubtitle),
              onTap: () => context.push('/profile/settings/change-password'),
            ),
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
