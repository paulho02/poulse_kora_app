import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/languages/language_providers.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../profile/application/profile_providers.dart';

/// Which languages this reader accepts posts in — one tab of
/// `FeedPreferencesScreen`, beside the channel list.
///
/// It sits here rather than in Settings because it is the same *kind* of thing
/// as subscribing to a channel: both shape what the feed sends you, neither is
/// an account preference. Settings keeps the app's own interface language,
/// which is a device preference and a genuinely different question — putting
/// the two in one list was what made them read as one setting twice.
///
/// Saves on each toggle rather than behind a Save button. The set is idempotent
/// and the server writes it absolutely, so there is no half-applied state to
/// protect against — and a Save button on a screen with two checkboxes is a
/// step whose only job is to be forgotten.
class ContentLanguagesTab extends ConsumerStatefulWidget {
  const ContentLanguagesTab({super.key});

  @override
  ConsumerState<ContentLanguagesTab> createState() =>
      _ContentLanguagesTabState();
}

class _ContentLanguagesTabState extends ConsumerState<ContentLanguagesTab> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _isSaving = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggle(List<String> current, String code, bool selected) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final next = [...current];
    if (selected) {
      if (!next.contains(code)) next.add(code);
    } else {
      next.remove(code);
    }
    if (next.isEmpty) {
      // Refused here as well as server-side, because the server's refusal would
      // arrive as an error toast over a checkbox that had already visibly
      // unticked. An empty set is an audience of nowhere: no route would ever
      // select this reader and their feed would stay empty with nothing saying
      // why.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.settingsContentLanguagesEmpty),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(profileProvider.notifier).setContentLanguages(next);
    } catch (error) {
      if (!mounted) return;
      // The list re-renders from the profile, which never changed — so the
      // checkbox springs back on its own and the message explains why.
      showErrorSnackBarOn(messenger, l10n, error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profileAsync = ref.watch(profileProvider);
    final languages = ref.watch(contentLanguagesProvider);

    return profileAsync.when(
      data: (profile) {
        final selected = profile.data.contentLanguages;
        // Filtered by the visible label, not the raw code — "de" the code and
        // "German" the label are both two-letter-unfriendly to search by code
        // alone once a reader doesn't know it.
        final filtered = _query.isEmpty
            ? languages
            : languages
                  .where(
                    (code) => contentLanguageLabel(
                      l10n,
                      code,
                    ).toLowerCase().contains(_query),
                  )
                  .toList();
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
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) =>
                    setState(() => _query = value.toLowerCase()),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(l10n.contentLanguagesNoneFound))
                  : ListView(
                      children: [
                        for (final code in filtered)
                          CheckboxListTile(
                            title: Text(contentLanguageLabel(l10n, code)),
                            value: selected.contains(code),
                            onChanged: _isSaving
                                ? null
                                : (value) =>
                                      _toggle(selected, code, value ?? false),
                          ),
                        // Named rather than left to be discovered: a reader who
                        // picks only a small language will see a feed that
                        // fills slowly, and without this the app just looks
                        // broken to them. Judged against the *whole* list, not
                        // the filtered one — a search query narrowing what's on
                        // screen must not make this claim about languages the
                        // reader never touched.
                        if (selected.length < languages.length)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            child: Text(
                              l10n.settingsContentLanguagesFewPosts,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorStateView(
        error: error,
        onRetry: () => ref.read(profileProvider.notifier).refresh(),
      ),
    );
  }
}
