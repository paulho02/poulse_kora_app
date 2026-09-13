import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/languages/language_providers.dart';

/// Opens the composer's language picker and resolves to the chosen language
/// code, or `null` if the sheet was dismissed without a choice.
///
/// [allowUnspecified] is false whenever the post contains any text. "No
/// language" reaches every subscriber of the channel rather than one language's
/// readers, so it is the widest audience a post can claim — the backend accepts
/// it only for a post with no text blocks, and the option is greyed out with a
/// reason here rather than being hidden, so an author who expected it learns
/// why it is unavailable instead of wondering where it went.
Future<String?> showLanguagePickerSheet(
  BuildContext context, {
  required String? selected,
  required bool allowUnspecified,
  String? suggested,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _LanguagePickerSheet(
      selected: selected,
      allowUnspecified: allowUnspecified,
      suggested: suggested,
    ),
  );
}

class _LanguagePickerSheet extends ConsumerWidget {
  const _LanguagePickerSheet({
    required this.selected,
    required this.allowUnspecified,
    required this.suggested,
  });

  final String? selected;
  final bool allowUnspecified;

  /// What the on-device detector made of the text, if anything. Shown as a
  /// badge rather than pre-selected here — the picker is opened precisely when
  /// someone wants to decide for themselves, and the suggestion has already
  /// been applied to the chip they tapped.
  final String? suggested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final languages = ref.watch(contentLanguagesProvider);
    final unspecified = ref.watch(languageUnspecifiedProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text(
                l10n.composerLanguageTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              // The one sentence that makes this choice make sense. Without it
              // a language picker on a composer reads as spell-check settings,
              // rather than as the thing that decides who receives the post.
              child: Text(
                l10n.composerLanguageHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final code in languages)
                    _LanguageTile(
                      label: contentLanguageLabel(l10n, code),
                      isSelected: code == selected,
                      isSuggested: code == suggested,
                      onTap: () => Navigator.of(context).pop(code),
                    ),
                  const Divider(height: 8, indent: 20, endIndent: 20),
                  _LanguageTile(
                    label: l10n.contentLanguageNone,
                    subtitle: allowUnspecified
                        ? l10n.contentLanguageNoneHint
                        : l10n.composerLanguageNoneUnavailable,
                    isSelected: unspecified == selected,
                    isSuggested: false,
                    onTap: allowUnspecified
                        ? () => Navigator.of(context).pop(unspecified)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.label,
    required this.isSelected,
    required this.isSuggested,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool isSelected;
  final bool isSuggested;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return ListTile(
      enabled: onTap != null,
      title: Row(
        children: [
          Flexible(child: Text(label)),
          if (isSuggested) ...[
            const SizedBox(width: 8),
            // A quiet badge, not a selection: the detector saves a tap, it does
            // not make the decision. Someone who disagrees is already here.
            Chip(
              label: Text(l10n.composerLanguageSuggested),
              labelStyle: theme.textTheme.labelSmall,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: isSelected
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}
