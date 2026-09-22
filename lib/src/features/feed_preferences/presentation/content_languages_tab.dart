import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import 'content_language_checklist.dart';

/// Which languages this reader accepts posts in — one tab of
/// `FeedPreferencesScreen`, beside the channel list.
///
/// It sits here rather than in Settings because it is the same *kind* of thing
/// as subscribing to a channel: both shape what the feed sends you, neither is
/// an account preference. Settings keeps the app's own interface language,
/// which is a device preference and a genuinely different question — putting
/// the two in one list was what made them read as one setting twice.
///
/// The list, and the saving rules that go with it, are
/// [ContentLanguageChecklist]; onboarding shows the same list without this
/// tab's chrome. What lives here is the framing a reader who *went looking* for
/// this screen needs, which is different from what a reader who was *sent* here
/// by onboarding needs.
class ContentLanguagesTab extends ConsumerStatefulWidget {
  const ContentLanguagesTab({super.key});

  @override
  ConsumerState<ContentLanguagesTab> createState() =>
      _ContentLanguagesTabState();
}

class _ContentLanguagesTabState extends ConsumerState<ContentLanguagesTab> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            l10n.settingsContentLanguagesDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // The disambiguation, right where the confusion happens. The two
        // language settings sit one tap apart and sound identical.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.settingsContentLanguagesNotAppLanguage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Pinned above the list rather than scrolling with it, matching the
        // channel tab — a field that scrolls out of view before you've
        // finished typing is a field you can no longer see yourself type
        // into.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.contentLanguagesSearchHint,
            ),
            onChanged: (value) => setState(() => _query = value.toLowerCase()),
          ),
        ),
        Expanded(child: ContentLanguageChecklist(query: _query)),
      ],
    );
  }
}
