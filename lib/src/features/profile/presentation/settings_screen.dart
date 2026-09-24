import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';

import '../../../core/presentation/language_picker.dart';
import '../../../core/settings/locale_settings.dart';
import '../../../core/tips/application/tip_providers.dart';
import '../../stats/application/stats_providers.dart';
import '../application/profile_providers.dart';
import 'data_export_tile.dart';
import 'delete_account_dialog.dart';
import 'google_link_tile.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
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
          // Which languages you accept *posts* in is not here — it lives in
          // Feed preferences, with the channel list, because it is a filter on
          // delivery rather than an account preference. This row is the app's
          // own interface language, and it keeps a subtitle saying so: the two
          // sound identical, and mistaking one for the other is invisible —
          // the app changes language and the feed does not.
          ListTile(
            leading: const Icon(Icons.smartphone_outlined),
            title: Text(l10n.settingsLanguageSectionHeader),
            subtitle: Text(l10n.settingsLanguageSubtitle),
            trailing: Text(localeLabel(l10n, localeOverride)),
            onTap: () => pickLanguage(context, ref),
          ),

          _SectionHeader(l10n.settingsSectionNotifications),
          // These two used to be live switches over two `bool` fields that
          // nothing read, nothing persisted and no notification system backed.
          // A switch is a promise that the thing it names will now happen, and
          // these promised nothing: flipping one survived until the screen was
          // popped and changed no behaviour ever. Worse, it failed in silence —
          // the only way to find out was to wait for a notification that was
          // never coming, and conclude the app was broken.
          //
          // So they are stated as what they are: the plan, disabled, under one
          // line saying when. Kept rather than deleted because the section is
          // a real roadmap item and its absence would read as "this app will
          // never notify me" — which is also wrong.
          _DisabledSetting(
            icon: Icons.notifications_outlined,
            title: l10n.settingsNewPostsNotification,
          ),
          _DisabledSetting(
            icon: Icons.mark_email_unread_outlined,
            title: l10n.settingsWeeklyDigestNotification,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              l10n.settingsNotificationsUnavailable,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
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
            title: Text(l10n.settingsHowPeerkolaWorks),
            subtitle: Text(l10n.settingsHowPeerkolaWorksSubtitle),
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
                // Above the divider, not below it: this is an ordinary account
                // action, and the row under the divider is the destructive one.
                // It has to come *before* deleting, though, because the copy of
                // your data is the thing you want while the account still
                // exists.
                const DataExportTile(),
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

/// A setting that is coming but is not here yet.
///
/// Deliberately *not* a disabled `SwitchListTile`: a greyed-out switch still
/// shows a position, so it answers "is this on?" with a lie in one direction or
/// the other. This shows a badge instead, which has no state to misread.
class _DisabledSetting extends StatelessWidget {
  const _DisabledSetting({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return ListTile(
      enabled: false,
      leading: Icon(icon, color: muted),
      title: Text(title, style: TextStyle(color: muted)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          l10n.settingsComingSoonBadge,
          style: theme.textTheme.labelSmall?.copyWith(color: muted),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // More room above than below, so each header reads as belonging to the
      // rows under it rather than floating between two groups. It used to be
      // 20/8, which is close enough to even that a long settings list looked
      // like one undivided column of text.
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 6),
      child: Text(
        label.toUpperCase(),
        // In the accent, and bolder. These are the only signposts on a screen
        // that is otherwise thirteen near-identical rows, and drawn in plain
        // `labelSmall` they were quieter than the row labels they organise.
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
