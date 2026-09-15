import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';

/// The quiet mark on a post that is really a trust check (see `Post.isProbe`).
///
/// It exists because measuring people without telling them is a trick played on
/// the reader. A check earns its answer honestly or not at all, so there has to
/// be *something* here — but it has to stay small, for a reason that is easy to
/// get backwards: a marker loud enough to spot from across the feed would let a
/// reader sort checks from posts without reading either, and the score would
/// then measure how well people spot badges. Quiet enough that finding it costs
/// about as much attention as reading the card is the whole design.
///
/// So: no colour of its own, no fill, no border — a single small outline glyph
/// at label size, sitting in the meta line among the channel name and the age.
/// It reads as punctuation until you look at it.
///
/// It carries a tooltip and a semantics label rather than a visible word,
/// because the words that would fit ("check", "test") are exactly the ones that
/// make it scannable. A reader who long-presses it, or who uses a screen reader,
/// gets told plainly — neither of those is a way to skim.
class ProbeMarker extends StatelessWidget {
  const ProbeMarker({super.key, this.size = 13});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Tooltip(
      message: l10n.probeMarkerTooltip,
      child: Icon(
        Icons.science_outlined,
        size: size,
        // The meta line's own ink, not an accent: anything that stood out from
        // the text beside it would be findable without reading.
        color: theme.textTheme.labelSmall?.color,
        semanticLabel: l10n.probeMarkerTooltip,
      ),
    );
  }
}
