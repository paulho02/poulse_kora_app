import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';

/// How long the score takes to pop in, and how long it then holds before the
/// caller's own exit animation takes over. Shared so the feed card and the
/// full-screen view keep the same beat.
const Duration kForwardScorePopIn = Duration(milliseconds: 320);
const Duration kForwardScoreHold = Duration(milliseconds: 420);

/// The post's forwarding score, revealed for one beat *after* the reader's own
/// verdict and never before it.
///
/// The server is what enforces the "never before" half: the count rides on a
/// review's response and is deliberately absent from the post itself (see
/// `PostReviewResult`, and the rule in the backend's CLAUDE.md). A reader who
/// can see that everyone else forwarded a post is voting on the crowd rather
/// than on the post. Hence this widget takes a number from a review result and
/// offers no way to read one off a [Post] — there is nothing there to read.
///
/// Loudness scales with the number on a **logarithmic** curve. Every forward
/// re-fans the post out to more readers, so counts compound: on a linear ramp
/// almost every real post would look identical and only freak ones would
/// register at all. Here 1 is a quiet grey chip, ~7 is solidly accented, and 50
/// glows.
class ForwardScoreBadge extends StatelessWidget {
  const ForwardScoreBadge({
    super.key,
    required this.count,
    required this.animation,
  });

  /// Forwards the post has now, counting the review that just happened.
  final int count;

  /// 0 = absent, 1 = fully popped.
  final Animation<double> animation;

  /// The count that reads as "everything" — heat is flat out from here up.
  static const int _fullHeatAt = 1000;

  /// 0..1, how remarkable this number is. A first forward is deliberately cold:
  /// on a post nobody else has passed on yet, the reader *is* the score.
  static double heatFor(int count) => count <= 1
      ? 0
      : (math.log(count) / math.log(_fullHeatAt)).clamp(0.0, 1.0);

  static Color _backgroundFor(double heat, ColorScheme scheme) {
    // Amber, from the channel palette — a third stop past the accent, so a
    // genuinely viral post doesn't just look like a slightly bigger ordinary
    // one. The midpoint lands at 7 forwards.
    const hot = Color(0xFFF59E0B);
    return heat < 0.5
        ? Color.lerp(
            scheme.surfaceContainerHighest,
            scheme.primary,
            heat / 0.5,
          )!
        : Color.lerp(scheme.primary, hot, (heat - 0.5) / 0.5)!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final heat = heatFor(count);
    final background = _backgroundFor(heat, theme.colorScheme);
    // Derived, not picked per tier: the background sweeps grey → accent → amber
    // across two themes, and no single fixed ink stays legible over all of it.
    final ink =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return Semantics(
      liveRegion: true,
      label: l10n.postForwardScoreAnnouncement(count),
      // The glyphs underneath would otherwise be read out as a bare number,
      // which says nothing about what was counted.
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
            padding: EdgeInsets.symmetric(
              horizontal: 14 + 4 * heat,
              vertical: 6 + 3 * heat,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
              // The glow is the part that carries across a quick glance, so it
              // ramps harder than the size does.
              boxShadow: heat == 0
                  ? null
                  : [
                      BoxShadow(
                        color: background.withValues(alpha: 0.55 * heat),
                        blurRadius: 10 + 22 * heat,
                        spreadRadius: 1 + 3 * heat,
                      ),
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_forward, size: 16 + 6 * heat, color: ink),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 22 + 10 * heat,
                    height: 1,
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
