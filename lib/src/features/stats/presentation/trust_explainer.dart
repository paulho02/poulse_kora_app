import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/slide_up_route.dart';
import '../application/stats_providers.dart';

/// The one place Reviewer Trust is explained in full sentences.
///
/// It is the counterpart to `economy_explainer.dart`, and deliberately the same
/// shape: a full-screen [slideUpRoute] rather than a bottom sheet, live figures
/// at the top, then a short list of points. A sheet would arrive already
/// scrolled, and an explanation read through a letterbox is the one thing that
/// must not happen to an explanation.
///
/// **What it says, and what it must not.** A reader is entitled to know that
/// something is measuring them, what it costs them, and roughly what moves it.
/// They are not owed the coefficients, and publishing them would be a mistake:
/// the score is only worth anything while the cheapest way to raise it is to
/// read the posts. So this names the three inputs and stays vague about their
/// weights — it is an honest account, not a specification.
///
/// It leads with the effect rather than the number, because the number alone is
/// unactionable. "Your forwards reach 4 people instead of 3" is a sentence
/// someone can do something about; "your trust is 78" is trivia.
Future<void> showTrustExplainer(BuildContext context) {
  return Navigator.of(
    context,
  ).push<void>(slideUpRoute(builder: (context) => const _TrustExplainerPage()));
}

/// The small round "i" that opens it, for the trust figure to sit next to.
class TrustInfoButton extends StatelessWidget {
  const TrustInfoButton({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return IconButton(
      onPressed: () => showTrustExplainer(context),
      icon: Icon(Icons.info_outline, size: size),
      color: theme.colorScheme.onSurfaceVariant,
      tooltip: l10n.trustExplainerTitle,
      // A stat tile is a tight row; the default 48px IconButton would push the
      // number off its baseline. Shrunk to the glyph, with the tap target kept
      // at the platform minimum by the padding rather than by the box.
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}

class _TrustExplainerPage extends ConsumerWidget {
  const _TrustExplainerPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // The window is the server's to decide, so the sentence quotes it rather
    // than hardcoding a number that could drift out of step with the backend.
    // Null only in the moment before the stats land, which is why there is a
    // second, number-free wording rather than a placeholder digit.
    final windowDays = ref
        .watch(statsProvider)
        .maybeWhen(
          data: (cached) => cached.data.trustWindowDays,
          orElse: () => null,
        );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SlideDownDismissHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.trustExplainerTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.commonClose,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _LiveFigures(),
                    const SizedBox(height: 20),
                    _Point(
                      icon: Icons.travel_explore_outlined,
                      text: l10n.trustExplainerWhat,
                    ),
                    _Point(
                      icon: Icons.podcasts_outlined,
                      text: l10n.trustExplainerEffect,
                    ),
                    _Point(
                      icon: Icons.science_outlined,
                      text: l10n.trustExplainerChecks,
                    ),
                    _Point(
                      icon: Icons.menu_book_outlined,
                      text: l10n.trustExplainerReading,
                    ),
                    _Point(
                      icon: Icons.history_toggle_off,
                      text: windowDays == null
                          ? l10n.trustExplainerRecentUnknown
                          : l10n.trustExplainerRecent(windowDays),
                    ),
                    _Point(
                      icon: Icons.thumb_up_off_alt,
                      text: l10n.trustExplainerNoQuota,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The score and, more usefully, what it currently does.
///
/// Renders nothing if the stats have not loaded — this page is worth reading on
/// its own and should not turn into an error state, exactly as the economy
/// explainer's figures panel does not.
class _LiveFigures extends ConsumerWidget {
  const _LiveFigures();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return ref
        .watch(statsProvider)
        .maybeWhen(
          data: (cached) {
            final stats = cached.data;
            final (icon, tint, bandLabel) = switch (stats.trustBand) {
              'high' => (
                Icons.trending_up,
                theme.colorScheme.primary,
                l10n.trustBandHigh,
              ),
              'low' => (
                Icons.trending_down,
                theme.colorScheme.error,
                l10n.trustBandLow,
              ),
              _ => (
                Icons.trending_flat,
                theme.colorScheme.onSurfaceVariant,
                l10n.trustBandNormal,
              ),
            };

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: tint),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.trustExplainerScore(stats.trustScore, bandLabel),
                          style: theme.textTheme.titleSmall,
                        ),
                        // The consequence, in people. A reader can act on this
                        // sentence; they cannot act on "78 out of 100".
                        if (stats.trustFanout > 0)
                          Text(
                            l10n.trustExplainerReach(stats.trustFanout),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
          orElse: () => const SizedBox.shrink(),
        );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
