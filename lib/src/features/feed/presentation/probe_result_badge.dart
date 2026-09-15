import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import 'forward_score_badge.dart';

/// What a trust check says back, in the beat where an ordinary post would show
/// its forwarding score.
///
/// A probe has no score to show. It is created for exactly one reader and goes
/// no further, so its counters could only ever read "1 of 1" — a true number
/// that means nothing, and one that would quietly teach readers to recognise a
/// check by its result rather than by reading it. So the server zeroes them and
/// sets `isProbe`, and this takes their place.
///
/// It tells the reader whether they got it right, which is deliberate. The
/// alternative is that the only feedback a careless reader ever gets is their
/// forwards quietly reaching fewer people, with nothing to connect that to
/// anything they did. Being told costs nothing: answering correctly *is*
/// reading, so a reader who learns to take checks seriously has learned the
/// thing the score is trying to measure.
///
/// Uses the same pop-in animation and hold as [ForwardScoreBadge] so the two
/// land with an identical rhythm — a check that resolved faster or slower than
/// a post would be a tell in itself.
class ProbeResultBadge extends StatelessWidget {
  const ProbeResultBadge({
    super.key,
    required this.correct,
    required this.animation,
  });

  /// Whether the reader answered as the check asked, or null when the server
  /// had nothing to score it against. Null reads as a neutral acknowledgement:
  /// claiming right or wrong when neither is known would be worse than saying
  /// only that it was a check.
  final bool? correct;

  /// 0 = absent, 1 = fully popped.
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final scheme = theme.colorScheme;

    final (background, icon, label) = switch (correct) {
      true => (scheme.primary, Icons.check_rounded, l10n.probeResultCorrect),
      false => (
        scheme.errorContainer,
        Icons.close_rounded,
        l10n.probeResultWrong,
      ),
      null => (
        scheme.surfaceContainerHighest,
        Icons.science_outlined,
        l10n.probeResultNeutral,
      ),
    };
    // Derived rather than picked per case: these three backgrounds span accent,
    // error and surface across both themes, and no one fixed ink stays legible
    // over all of them.
    final ink =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Opacity(
            opacity: Curves.easeOut.transform(animation.value.clamp(0.0, 1.0)),
            child: Transform.scale(
              scale: Curves.elasticOut.transform(animation.value),
              child: child,
            ),
          ),
          child: Container(
            // Wider than the score badge and capped, because this one carries a
            // sentence rather than a number — at a phone's narrowest it has to
            // wrap inside the card instead of pushing past its edges.
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: background.withValues(alpha: 0.45),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: ink),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
