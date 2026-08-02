import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
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
            trailing: Text(_localeLabel(l10n, localeOverride)),
            onTap: () => _pickLanguage(context, ref, l10n, localeOverride),
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

String _localeLabel(AppLocalizations l10n, String? override) {
  switch (override) {
    case 'en':
      return l10n.settingsLanguageEnglish;
    case 'de':
      return l10n.settingsLanguageGerman;
    default:
      return l10n.settingsLanguageSystemDefault;
  }
}

Future<void> _pickLanguage(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  String? current,
) async {
  // `showDialog` returning `null` normally means "dismissed without choosing",
  // which collides with "System default" also being represented by `null` —
  // route every choice (including System default) through `Navigator.pop`
  // inside `onChanged` instead of relying on the dialog's own return value.
  await showDialog<void>(
    context: context,
    builder: (context) => RadioGroup<String?>(
      groupValue: current,
      onChanged: (value) async {
        Navigator.of(context).pop();
        await ref.read(localeOverrideProvider.notifier).setOverride(value);
      },
      child: SimpleDialog(
        title: Text(l10n.settingsLanguageDialogTitle),
        children: [
          RadioListTile<String?>(
            title: Text(l10n.settingsLanguageSystemDefault),
            value: null,
          ),
          RadioListTile<String?>(
            title: Text(l10n.settingsLanguageEnglish),
            value: 'en',
          ),
          RadioListTile<String?>(
            title: Text(l10n.settingsLanguageGerman),
            value: 'de',
          ),
        ],
      ),
    ),
  );
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
