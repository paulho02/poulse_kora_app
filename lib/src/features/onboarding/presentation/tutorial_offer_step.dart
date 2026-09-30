import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../tutorial/presentation/tutorial_illustrations.dart';

/// The fork between the intro slides and the rest of onboarding: read the
/// concept now, or go and find it out by using the app.
///
/// It is a step of its own rather than a "learn more" link on the last intro
/// slide, and the reason is that both answers have to look equally valid. A
/// link is an aside — nine out of ten people skim past it and then meet the
/// token economy as a surprise. Two buttons of the same size make the offer a
/// question that was actually asked, and the "no" a decision rather than an
/// omission.
///
/// Which is also why the Settings hint is on this screen and not only at the
/// end of the deck: the person who most needs to know the tutorial can be
/// re-opened is the one who just declined it.
class TutorialOfferStep extends StatelessWidget {
  const TutorialOfferStep({
    super.key,
    required this.onAccept,
    required this.onDecline,
  });

  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: (constraints.maxHeight * 0.38).clamp(
                          140.0,
                          240.0,
                        ),
                        child: const TutorialTeaser(),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        l10n.tutorialOfferTitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        l10n.tutorialOfferBody,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onAccept,
                    child: Text(l10n.tutorialOfferAccept),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onDecline,
                    child: Text(l10n.tutorialOfferDecline),
                  ),
                ),
                const SizedBox(height: 16),
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
                        l10n.tutorialSettingsHint,
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
        ],
      ),
    );
  }
}
