import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../feed_preferences/presentation/content_language_checklist.dart';

/// The onboarding flow's languages step: which languages this reader accepts
/// posts in, shown right after the channels they follow.
///
/// It exists because the backend narrows a new account to the locale its
/// registration request carried (`on_after_register`), and that default is
/// invisible from inside the app. A German phone therefore produced a
/// German-only reader who was never told so: their feed simply filled more
/// slowly than everyone else's, which reads as the app being quiet rather than
/// as a setting they could widen. The setting had a home — the Filters tab —
/// but nothing pointed a new account at it, and a filter you don't know is on
/// is indistinguishable from a platform with nothing on it.
///
/// **Not a decision that blocks the flow**, unlike the channel step before it.
/// The set is never empty (registration guarantees at least one language), so
/// Continue is always live and passing straight through is a legitimate answer
/// — the point is that the reader now knows what they are passing through. The
/// channel step blocks because an empty subscription list genuinely has no
/// sensible default.
///
/// The list, and the rules for saving it, are shared with the Filters tab
/// ([ContentLanguageChecklist]): each toggle writes the whole set immediately,
/// so there is no Save button here for someone to miss on their way to the next
/// step.
class ContentLanguagesStep extends StatelessWidget {
  const ContentLanguagesStep({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.onboardingLanguagesTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.onboardingLanguagesSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                // The actual point of the step. Without this line the ticked
                // boxes look like a choice the reader made, so there is nothing
                // to react to; with it, the one box ticked on a German phone
                // reads as a starting point and the empty one beside it as an
                // offer.
                Row(
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
                        l10n.onboardingLanguagesDefaultNote,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Expanded(child: ContentLanguageChecklist()),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onContinue,
                child: Text(l10n.commonContinue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
