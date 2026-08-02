import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../settings/locale_settings.dart';

/// Shared with the Settings language row — the label a given override (or
/// `null` for "follow the device") reads as.
String localeLabel(AppLocalizations l10n, String? override) {
  switch (override) {
    case 'en':
      return l10n.settingsLanguageEnglish;
    case 'de':
      return l10n.settingsLanguageGerman;
    default:
      return l10n.settingsLanguageSystemDefault;
  }
}

/// Opens the language-picker dialog and persists the choice via
/// `localeOverrideProvider`. Shared by [LanguagePickerButton] (login/register)
/// and the Settings language row, so there's one place to change the copy or
/// add a locale.
Future<void> pickLanguage(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final current = ref.read(localeOverrideProvider);
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

/// AppBar action opening the language picker — mirrors `ServerSettingsButton`
/// in placement/style, on the login and register screens specifically, so the
/// language can be set before an account even exists. Pure local preference
/// (see `core/settings/locale_settings.dart`): no login required to change it,
/// same as dark mode.
class LanguagePickerButton extends ConsumerWidget {
  const LanguagePickerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final override = ref.watch(localeOverrideProvider);
    return IconButton(
      icon: const Icon(Icons.language),
      tooltip: localeLabel(l10n, override),
      onPressed: () => pickLanguage(context, ref),
    );
  }
}
