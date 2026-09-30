import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/theme/app_colors.dart';

/// The animated drawings for the "How Peerkola works" tutorial, one per chapter.
///
/// Everything here is hand-drawn with [CustomPainter] over a single looping
/// [AnimationController] per chapter — deliberately no Lottie/Rive dependency
/// and no asset files. Two reasons, and both would still hold if a designer
/// handed us exported animations tomorrow:
///
/// - **They have to read in both themes.** An exported animation bakes its
///   colours in; these take every colour from `ColorScheme` at paint time, so
///   dark mode needs no second copy of anything.
/// - **They are diagrams, not artwork.** Dots, cards and arcs describing a
///   mechanic — a vector asset would be more bytes and another toolchain for
///   the same result, and the mechanic they describe is the part most likely
///   to change.
///
/// Two behaviours every illustration shares, both handled by [_Loop]:
///
/// - **It animates only while it is the visible page** ([active]). The deck is
///   a `PageView`, which builds the neighbouring pages too, so without this
///   three controllers would be ticking for one drawing anyone can see.
/// - **It honours reduced motion.** When the platform asks for it the loop
///   never starts and the painter is pinned to one representative frame
///   (`staticValue`), chosen per chapter as the moment the drawing states its
///   point most completely — never frame 0, which is generally an empty stage.
///
/// Note for tests: an active illustration repeats forever, so `pumpAndSettle`
/// on anything containing one will time out. Drive it with `pump(duration)`.
class TutorialIllustration extends StatelessWidget {
  const TutorialIllustration({
    super.key,
    required this.chapter,
    required this.active,
  });

  /// Zero-based index into the deck's chapters.
  final int chapter;

  /// Whether this is the page currently on screen.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return switch (chapter) {
      0 => _HandToHand(active: active),
      1 => _BroadcastVersusRelay(active: active),
      2 => _ForwardOrDrop(active: active),
      3 => _EarnAndSpend(active: active),
      _ => _QueueThatEnds(active: active),
    };
  }
}

/// The first chapter's drawing on its own, for the tutorial *offer* screen —
/// a still frame there would be a picture of nothing in particular, whereas
/// the relay itself is exactly what the offer is offering to explain.
class TutorialTeaser extends StatelessWidget {
  const TutorialTeaser({super.key});

  @override
  Widget build(BuildContext context) => const _HandToHand(active: true);
}

// ---------------------------------------------------------------- foundations

/// Every colour the painters draw with, resolved once from the theme.
///
/// Painters take this rather than a `BuildContext` because `paint` has no
/// context, and rather than a `ColorScheme` because two of the six are
/// derived (the accent follows the brightness, [onAccent] has to sit on top of
/// it) and deriving them per frame in five painters is five places to get it
/// wrong.
@immutable
class _Palette {
  const _Palette({
    required this.accent,
    required this.onAccent,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.card,
    required this.danger,
  });

  factory _Palette.of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Palette(
      accent: theme.brightness == Brightness.dark
          ? AppColors.accentDark
          : AppColors.accentLight,
      // The accent is a dark green in light mode and a light green in dark
      // mode, so the surface colour is the one that contrasts with it in both.
      onAccent: scheme.surface,
      ink: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      faint: scheme.outlineVariant,
      card: scheme.surfaceContainerHighest,
      danger: scheme.error,
    );
  }

  final Color accent;
  final Color onAccent;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color card;
  final Color danger;

  @override
  bool operator ==(Object other) =>
      other is _Palette &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.ink == ink &&
      other.muted == muted &&
      other.faint == faint &&
      other.card == card &&
      other.danger == danger;

  @override
  int get hashCode =>
      Object.hash(accent, onAccent, ink, muted, faint, card, danger);
}

/// Runs one illustration's clock. See [TutorialIllustration] for why `active`
/// and reduced motion are handled here rather than per painter.
class _Loop extends StatefulWidget {
  const _Loop({
    required this.active,
    required this.duration,
    required this.staticValue,
    required this.builder,
  });

  final bool active;
  final Duration duration;

  /// The frame to hold when the platform asks for reduced motion.
  final double staticValue;

  final Widget Function(BuildContext context, double t) builder;

  @override
  State<_Loop> createState() => _LoopState();
}

class _LoopState extends State<_Loop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  var _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Loop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    if (_reduceMotion) {
      _controller.stop();
      _controller.value = widget.staticValue;
      return;
    }
    if (widget.active) {
      // `repeat` resumes from the current value, so paging back to a chapter
      // picks its loop up where it was left rather than restarting it.
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => widget.builder(context, _controller.value),
  );
}

/// A caption strip under a drawing, for the two chapters whose animation shows
/// one thing and then its opposite.
///
/// It is a widget rather than text painted into the canvas so it stays
/// translated, themed and scalable with the reader's text size like every
/// other string in the app.
class _Caption extends StatelessWidget {
  const _Caption({
    required this.icon,
    required this.text,
    required this.color,
    required this.opacity,
  });

  final IconData icon;
  final String text;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The drawing on top, its caption underneath, the caption's height taken out
/// of the drawing rather than out of the page — so the two chapters with a
/// caption and the three without still hand the deck a box of the same size.
Widget _captioned({required Widget art, required Widget caption}) => Column(
  children: [
    Expanded(child: art),
    const SizedBox(height: 10),
    caption,
  ],
);

Widget _canvas(CustomPainter painter) =>
    CustomPaint(painter: painter, child: const SizedBox.expand());

// -------------------------------------------------------------- paint helpers

/// `t`'s progress through the window `[start, end]`, clamped outside it. Every
/// painter is one clock from 0 to 1, so this is how sub-phases are cut out of
/// it.
double _seg(double t, double start, double end) =>
    ((t - start) / (end - start)).clamp(0.0, 1.0);

double _ease(double x) => Curves.easeInOut.transform(x.clamp(0.0, 1.0));

/// A reader: head and shoulders, small enough to read as a person at 20px.
void _person(Canvas canvas, Offset centre, double r, Color color) {
  final paint = Paint()..color = color;
  canvas.drawCircle(Offset(centre.dx, centre.dy - r * 0.38), r * 0.30, paint);
  canvas.drawArc(
    Rect.fromCenter(
      center: Offset(centre.dx, centre.dy + r * 0.48),
      width: r * 1.24,
      height: r * 1.05,
    ),
    math.pi,
    math.pi,
    false,
    paint,
  );
}

/// A person inside a disc — the shared node of chapters 1, 2 and 3. [lit] is
/// how far along the "has this reached them yet" transition the node is, so a
/// caller can cross-fade it rather than flipping it.
void _node(
  Canvas canvas,
  Offset centre,
  double r,
  _Palette palette, {
  required double lit,
  double opacity = 1.0,
}) {
  final l = lit.clamp(0.0, 1.0);
  // The reached state is a *filled* disc with the figure knocked out of it,
  // not an accent figure on an accent disc — same hue on same hue made the
  // person disappear exactly when the drawing most needed them to be a person.
  canvas.drawCircle(
    centre,
    r,
    Paint()
      ..color = Color.lerp(
        palette.faint.withValues(alpha: 0.45 * opacity),
        palette.accent.withValues(alpha: 0.95 * opacity),
        l,
      )!,
  );
  _person(
    canvas,
    centre,
    r,
    Color.lerp(
      palette.muted.withValues(alpha: 0.6 * opacity),
      palette.onAccent.withValues(alpha: opacity),
      l,
    )!,
  );
}

/// The post itself: a card with three text lines. Small, and always the same
/// shape, so it stays recognisable as "one post" while it moves between
/// chapters.
void _postCard(
  Canvas canvas,
  Offset centre,
  double width,
  _Palette palette, {
  double opacity = 1.0,
  double rotation = 0.0,
  Color? tint,
}) {
  if (opacity <= 0.01 || width <= 0.5) return;
  final height = width * 1.18;
  final body = tint ?? palette.accent;

  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  canvas.rotate(rotation);

  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: width, height: height),
      Radius.circular(width * 0.22),
    ),
    // `body.a` rather than a flat 1: a caller passing a translucent tint (an
    // unreviewed post in chapter 4) means it.
    Paint()..color = body.withValues(alpha: body.a * 0.95 * opacity),
  );
  final line = Paint()
    ..color = palette.onAccent.withValues(alpha: 0.85 * opacity)
    ..strokeWidth = math.max(1.0, width * 0.09)
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 3; i++) {
    final y = -height * 0.23 + i * height * 0.23;
    final length = width * (i == 2 ? 0.30 : 0.50);
    canvas.drawLine(
      Offset(-width * 0.26, y),
      Offset(-width * 0.26 + length, y),
      line,
    );
  }
  canvas.restore();
}

/// A point along a quadratic arc from [a] to [b], bulging away from the line
/// between them. The post is carried *over* the readers rather than through
/// them, which is what keeps the card from sitting on top of a face.
Offset _arcPoint(Offset a, Offset b, double u) {
  final lift = (b - a).distance * 0.30;
  final control = Offset((a.dx + b.dx) / 2, math.min(a.dy, b.dy) - lift);
  final m = 1 - u;
  return Offset(
    m * m * a.dx + 2 * m * u * control.dx + u * u * b.dx,
    m * m * a.dy + 2 * m * u * control.dy + u * u * b.dy,
  );
}

/// A "done" badge: the accent knocked out of a light disc, so it stays legible
/// on the accent-tinted card it sits on.
void _checkBadge(
  Canvas canvas,
  Offset centre,
  double r,
  _Palette palette,
  double progress,
) {
  if (progress <= 0.02) return;
  final rr = r * Curves.easeOutBack.transform(progress.clamp(0.0, 1.0));
  if (rr <= 0.5) return;
  canvas.drawCircle(centre, rr, Paint()..color = palette.onAccent);
  canvas.drawPath(
    Path()
      ..moveTo(centre.dx - rr * 0.40, centre.dy)
      ..lineTo(centre.dx - rr * 0.08, centre.dy + rr * 0.32)
      ..lineTo(centre.dx + rr * 0.44, centre.dy - rr * 0.34),
    _stroke(palette.accent, math.max(1.2, rr * 0.26)),
  );
}

Paint _stroke(Color color, double width) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..color = color;

// ------------------------------------------------- 1. a post, hand to hand

class _HandToHand extends StatelessWidget {
  const _HandToHand({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = _Palette.of(context);
    return _Loop(
      active: active,
      duration: const Duration(milliseconds: 5600),
      // Two of the four readers reached: the drawing is mid-relay rather than
      // finished, which is the state the chapter is about.
      staticValue: 0.55,
      builder: (context, t) =>
          _canvas(_HandToHandPainter(t: t, palette: palette)),
    );
  }
}

class _HandToHandPainter extends CustomPainter {
  _HandToHandPainter({required this.t, required this.palette});

  final double t;
  final _Palette palette;

  static const _nodeCount = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.height * 0.155, size.width * 0.085);
    final left = size.width * 0.14;
    final step = (size.width * 0.72) / (_nodeCount - 1);
    final baseline = size.height * 0.72;
    final nodes = [
      for (var i = 0; i < _nodeCount; i++)
        Offset(
          left + step * i,
          baseline - (i.isOdd ? size.height * 0.13 : 0.0),
        ),
    ];
    // Where the card rides while it is being handed over: clear above the
    // heads, so it never lands on the face it is being handed to.
    final hands = [for (final n in nodes) n.translate(0, -r * 2.05)];

    final hops = _nodeCount - 1;
    const start = 0.08;
    const end = 0.78;
    final travel = _seg(t, start, end) * hops;
    // Lighting is driven by *when the post got there*, not by how far along
    // the path it is. Deriving it from `travel` left the last reader unlit
    // forever: their arrival is the moment the journey ends, so there is no
    // remaining travel to ramp them up with.
    double arrival(int i) => start + (end - start) * i / hops;

    for (var i = 0; i < hops; i++) {
      final done = (travel - i).clamp(0.0, 1.0);
      canvas.drawLine(nodes[i], nodes[i + 1], _stroke(palette.faint, 2));
      if (done > 0) {
        canvas.drawLine(
          nodes[i],
          Offset.lerp(nodes[i], nodes[i + 1], done)!,
          _stroke(palette.accent.withValues(alpha: 0.7), 2.4),
        );
      }
    }

    for (var i = 0; i < _nodeCount; i++) {
      // A ring that expands away once, the moment the post lands.
      final pulse = _seg(t, arrival(i), arrival(i) + 0.16);
      if (t >= arrival(i) && pulse < 1) {
        canvas.drawCircle(
          nodes[i],
          r * (1 + 0.9 * pulse),
          _stroke(palette.accent.withValues(alpha: 0.45 * (1 - pulse)), 2),
        );
      }
      _node(
        canvas,
        nodes[i],
        r,
        palette,
        lit: _seg(t, arrival(i), arrival(i) + 0.05),
      );
    }

    final fadeOut = 1 - _seg(t, 0.84, 0.94);
    final Offset card;
    if (travel <= 0) {
      card = Offset.lerp(
        hands.first.translate(0, -size.height * 0.5),
        hands.first,
        Curves.easeOutCubic.transform(_seg(t, 0.0, start)),
      )!;
    } else {
      final hop = travel.floor().clamp(0, hops - 1);
      card = _arcPoint(hands[hop], hands[hop + 1], _ease(travel - hop));
    }
    _postCard(canvas, card, r * 1.05, palette, opacity: fadeOut);
  }

  @override
  bool shouldRepaint(_HandToHandPainter old) =>
      old.t != t || old.palette != palette;
}

// ------------------------------------------- 2. broadcast versus the relay

class _BroadcastVersusRelay extends StatelessWidget {
  const _BroadcastVersusRelay({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = _Palette.of(context);
    final l10n = AppLocalizations.of(context);
    return _Loop(
      active: active,
      duration: const Duration(milliseconds: 7200),
      // The relay half, part-way along: the comparison only lands once the
      // second mechanic is on screen, and this is where it differs most.
      staticValue: 0.80,
      builder: (context, t) {
        final mode = _ease(_seg(t, 0.42, 0.54));
        return _captioned(
          art: _canvas(_BroadcastRelayPainter(t: t, palette: palette)),
          caption: Stack(
            alignment: Alignment.center,
            children: [
              _Caption(
                icon: Icons.podcasts,
                text: l10n.tutorialChapter2LabelConventional,
                color: palette.muted,
                opacity: 1 - mode,
              ),
              _Caption(
                icon: Icons.hub_outlined,
                text: l10n.tutorialChapter2LabelPeerkola,
                color: palette.accent,
                opacity: mode,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The same six readers, reached two ways.
///
/// Keeping the audience identical across both halves is the whole point: the
/// difference the chapter is describing is the *mechanism*, not the crowd, and
/// re-drawing the crowd would invite the reader to compare the wrong thing.
class _BroadcastRelayPainter extends CustomPainter {
  _BroadcastRelayPainter({required this.t, required this.palette});

  final double t;
  final _Palette palette;

  static const _nodeCount = 6;

  /// How far the relay half gets before it stops. Deliberately short of the
  /// full row: reach ends where people stop passing a post on, and a chain
  /// that always lit everybody would say the opposite of the chapter.
  static const _relayReach = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.height * 0.115, size.width * 0.058);
    final left = size.width * 0.10;
    final step = (size.width * 0.80) / (_nodeCount - 1);
    final nodes = [
      for (var i = 0; i < _nodeCount; i++)
        Offset(
          left + step * i,
          size.height * 0.80 -
              size.height * 0.06 * math.sin(math.pi * i / (_nodeCount - 1)),
        ),
    ];

    final mode = _ease(_seg(t, 0.42, 0.54));
    final source = Offset.lerp(
      Offset(size.width * 0.5, size.height * 0.16),
      Offset(left, size.height * 0.26),
      mode,
    )!;

    // --- the broadcast half: every reader, at once, from one place.
    final rays = Curves.easeOutCubic.transform(_seg(t, 0.06, 0.34));
    if (mode < 1) {
      final rayPaint = _stroke(
        palette.muted.withValues(alpha: 0.45 * (1 - mode)),
        2,
      );
      for (final n in nodes) {
        canvas.drawLine(source, Offset.lerp(source, n, rays)!, rayPaint);
      }
      for (var k = 0; k < 2; k++) {
        final p = (t * 3 + k * 0.5) % 1.0;
        canvas.drawCircle(
          source,
          r * (0.9 + 2.4 * p),
          _stroke(
            palette.muted.withValues(alpha: 0.30 * (1 - p) * (1 - mode)),
            1.6,
          ),
        );
      }
    }

    // --- the relay half: one hop at a time, and only as far as it gets.
    final path = [source, ...nodes.take(_relayReach)];
    const relayStart = 0.58;
    const relayEnd = 0.92;
    final travel = _seg(t, relayStart, relayEnd) * (path.length - 1);
    // Same reason as chapter 1: the last reader in the chain is lit by the
    // clock, not by leftover travel there isn't any of.
    double arrival(int i) =>
        relayStart + (relayEnd - relayStart) * (i + 1) / (path.length - 1);
    if (mode > 0) {
      for (var i = 0; i < path.length - 1; i++) {
        final done = (travel - i).clamp(0.0, 1.0);
        canvas.drawLine(
          path[i],
          path[i + 1],
          _stroke(palette.faint.withValues(alpha: 0.6 * mode), 2),
        );
        if (done > 0) {
          canvas.drawLine(
            path[i],
            Offset.lerp(path[i], path[i + 1], done)!,
            _stroke(palette.accent.withValues(alpha: 0.75 * mode), 2.4),
          );
        }
      }
    }

    final litBroadcast = ((rays - 0.85) / 0.15).clamp(0.0, 1.0);
    for (var i = 0; i < _nodeCount; i++) {
      final litRelay = i < _relayReach
          ? _seg(t, arrival(i), arrival(i) + 0.04)
          : 0.0;
      _node(
        canvas,
        nodes[i],
        r,
        palette,
        lit: litBroadcast * (1 - mode) + litRelay * mode,
      );
    }

    // The source: a ranking engine on the left of the loop, the post's author
    // on the right of it. One shape, because it occupies the same role.
    _postCard(
      canvas,
      source,
      r * 1.3,
      palette,
      tint: Color.lerp(palette.muted, palette.accent, mode),
    );

    if (mode > 0 && travel > 0) {
      final hop = travel.floor().clamp(0, path.length - 2);
      _postCard(
        canvas,
        Offset.lerp(
          path[hop],
          path[hop + 1],
          _ease(travel - hop),
        )!.translate(0, -r * 1.5),
        r * 1.05,
        palette,
        opacity: mode,
      );
    }
  }

  @override
  bool shouldRepaint(_BroadcastRelayPainter old) =>
      old.t != t || old.palette != palette;
}

// ------------------------------------------------------ 3. forward or drop

class _ForwardOrDrop extends StatelessWidget {
  const _ForwardOrDrop({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = _Palette.of(context);
    final l10n = AppLocalizations.of(context);
    return _Loop(
      active: active,
      duration: const Duration(milliseconds: 7600),
      // Mid-forward: the outcome that has somewhere to go is the one worth
      // holding still on.
      staticValue: 0.34,
      builder: (context, t) {
        final forwarding = t < 0.5;
        final local = (forwarding ? t : t - 0.5) / 0.5;
        // Fade the caption at both ends of its half so the swap reads as one
        // label replacing the other rather than as a jump cut.
        final opacity = math.min(
          _seg(local, 0.0, 0.10),
          1 - _seg(local, 0.92, 1.0),
        );
        return _captioned(
          art: _canvas(_ForwardOrDropPainter(t: t, palette: palette)),
          caption: Stack(
            alignment: Alignment.center,
            children: [
              _Caption(
                icon: Icons.forward_outlined,
                text: l10n.tutorialChapter3LabelForward,
                color: palette.accent,
                opacity: forwarding ? opacity : 0,
              ),
              _Caption(
                icon: Icons.close_rounded,
                text: l10n.tutorialChapter3LabelDrop,
                color: palette.danger,
                opacity: forwarding ? 0 : opacity,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ForwardOrDropPainter extends CustomPainter {
  _ForwardOrDropPainter({required this.t, required this.palette});

  final double t;
  final _Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.height * 0.15, size.width * 0.082);
    final you = Offset(size.width * 0.20, size.height * 0.55);
    final hand = Offset(size.width * 0.46, size.height * 0.50);
    final onward = [
      Offset(size.width * 0.72, size.height * 0.22),
      Offset(size.width * 0.86, size.height * 0.55),
      Offset(size.width * 0.72, size.height * 0.88),
    ];

    final forwarding = t < 0.5;
    final local = (forwarding ? t : t - 0.5) / 0.5;

    // arrive -> hold (the decision) -> outcome -> clear
    final arrive = Curves.easeOutCubic.transform(_seg(local, 0.02, 0.30));
    final outcome = _seg(local, 0.44, 0.88);
    final clear = _seg(local, 0.90, 1.0);

    // The reader making the call, ringed so they read as "you" rather than as
    // one more node in the row.
    canvas.drawCircle(
      you,
      r * 1.28,
      _stroke(palette.accent.withValues(alpha: 0.45), 2),
    );
    _node(canvas, you, r, palette, lit: 1);

    final reached = forwarding ? outcome : 0.0;
    for (var i = 0; i < onward.length; i++) {
      // Staggered, so three readers are three arrivals rather than one event.
      final progress = ((reached - i * 0.12) / 0.62).clamp(0.0, 1.0);
      if (forwarding && progress > 0) {
        canvas.drawLine(
          hand,
          Offset.lerp(hand, onward[i], progress)!,
          _stroke(palette.accent.withValues(alpha: 0.55), 2),
        );
        _postCard(
          canvas,
          Offset.lerp(hand, onward[i], progress)!,
          r * 0.62,
          palette,
          opacity: progress < 1 ? 1 : 0,
        );
      }
      _node(canvas, onward[i], r * 0.82, palette, lit: progress);
    }

    // The post in hand: slides in, waits on the decision, then either travels
    // or falls out of the drawing.
    final entry = Offset.lerp(
      Offset(hand.dx, -size.height * 0.3),
      hand,
      arrive,
    )!;
    if (forwarding) {
      final leave = _seg(local, 0.44, 0.66);
      _postCard(
        canvas,
        Offset.lerp(entry, hand.translate(size.width * 0.06, 0), leave)!,
        r * 1.1,
        palette,
        opacity: (1 - leave) * (1 - clear),
      );
    } else {
      final fall = Curves.easeInCubic.transform(outcome);
      _postCard(
        canvas,
        entry.translate(0, size.height * 0.55 * fall),
        r * 1.1,
        palette,
        opacity: (1 - fall) * (1 - clear),
        rotation: fall * 0.6,
        tint: Color.lerp(palette.accent, palette.danger, fall * 0.8),
      );
      // The stop mark, drawn where the post was let go of.
      final mark = _seg(local, 0.50, 0.70) * (1 - clear);
      if (mark > 0) {
        final arm = r * 0.5 * mark;
        final cross = _stroke(
          palette.danger.withValues(alpha: 0.8 * mark),
          2.6,
        );
        canvas.drawLine(
          hand.translate(-arm, -arm),
          hand.translate(arm, arm),
          cross,
        );
        canvas.drawLine(
          hand.translate(arm, -arm),
          hand.translate(-arm, arm),
          cross,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ForwardOrDropPainter old) =>
      old.t != t || old.palette != palette;
}

// ------------------------------------------------------- 4. earn and spend

class _EarnAndSpend extends StatelessWidget {
  const _EarnAndSpend({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = _Palette.of(context);
    return _Loop(
      active: active,
      duration: const Duration(milliseconds: 8200),
      // Balance full, about to be spent — the frame where both halves of the
      // exchange are visible at once.
      staticValue: 0.58,
      builder: (context, t) =>
          _canvas(_EarnAndSpendPainter(t: t, palette: palette)),
    );
  }
}

class _EarnAndSpendPainter extends CustomPainter {
  _EarnAndSpendPainter({required this.t, required this.palette});

  final double t;
  final _Palette palette;

  static const _reviews = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final cardWidth = math.min(size.width * 0.11, size.height * 0.20);
    final reviewY = size.height * 0.26;
    final reviewed = [
      for (var i = 0; i < _reviews; i++)
        Offset(size.width * (0.30 + 0.20 * i), reviewY),
    ];

    final barLeft = size.width * 0.14;
    final barRight = size.width * 0.86;
    final barY = size.height * 0.76;
    final barHeight = math.max(8.0, size.height * 0.085);
    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        barLeft,
        barY - barHeight / 2,
        barRight,
        barY + barHeight / 2,
      ),
      Radius.circular(barHeight / 2),
    );

    // Each review earns; the balance is spent once it can afford a post.
    final spend = _seg(t, 0.62, 0.76);
    var fill = 0.0;
    for (var i = 0; i < _reviews; i++) {
      final start = 0.08 + 0.16 * i;
      fill += _seg(t, start + 0.11, start + 0.15) / _reviews;
    }
    fill *= 1 - spend;

    canvas.drawRRect(
      barRect,
      Paint()..color = palette.faint.withValues(alpha: 0.4),
    );
    if (fill > 0.001) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            barLeft,
            barY - barHeight / 2,
            barLeft + (barRight - barLeft) * fill,
            barY + barHeight / 2,
          ),
          Radius.circular(barHeight / 2),
        ),
        Paint()..color = palette.accent.withValues(alpha: 0.85),
      );
    }

    // Reviewing: a post gets a decision, and a token comes back for it.
    for (var i = 0; i < _reviews; i++) {
      final start = 0.08 + 0.16 * i;
      final done = _seg(t, start, start + 0.04);
      final flight = _ease(_seg(t, start + 0.04, start + 0.14));
      final fading = 1 - _seg(t, 0.88, 1.0);
      _postCard(
        canvas,
        reviewed[i],
        cardWidth,
        palette,
        // Unreviewed posts sit back at a third of the ink: they are other
        // people's, and the drawing is about what happens to them, not about
        // them.
        tint: Color.lerp(
          palette.muted.withValues(alpha: 0.5),
          palette.accent,
          done,
        ),
        opacity: fading,
      );
      _checkBadge(
        canvas,
        reviewed[i].translate(cardWidth * 0.46, cardWidth * 0.52),
        cardWidth * 0.34,
        palette,
        done * fading,
      );
      if (flight > 0 && flight < 1) {
        final target = Offset(
          barLeft + (barRight - barLeft) * ((i + 0.5) / _reviews),
          barY,
        );
        _token(
          canvas,
          _arcPoint(reviewed[i].translate(0, cardWidth * 0.8), target, flight),
          cardWidth * 0.38,
        );
      }
    }

    // Publishing: the balance drops and a post of your own leaves.
    final launch = _seg(t, 0.72, 0.94);
    if (launch > 0) {
      final from = Offset((barLeft + barRight) / 2, barY - barHeight);
      // A straight rise rather than an arc: an arc's lift carried the post up
      // through the row of reviewed ones, which read as it going back where it
      // came from.
      final to = Offset(size.width * 1.12, size.height * 0.44);
      _postCard(
        canvas,
        Offset.lerp(from, to, _ease(launch))!,
        cardWidth * 1.25,
        palette,
        opacity: 1 - _seg(t, 0.88, 0.98),
      );
    }
  }

  void _token(Canvas canvas, Offset centre, double r) {
    canvas.drawCircle(centre, r, Paint()..color = palette.accent);
    canvas.drawCircle(
      centre,
      r * 0.55,
      _stroke(palette.onAccent.withValues(alpha: 0.9), math.max(1.0, r * 0.22)),
    );
  }

  @override
  bool shouldRepaint(_EarnAndSpendPainter old) =>
      old.t != t || old.palette != palette;
}

// -------------------------------------------------- 5. a queue that can end

class _QueueThatEnds extends StatelessWidget {
  const _QueueThatEnds({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = _Palette.of(context);
    return _Loop(
      active: active,
      duration: const Duration(milliseconds: 9000),
      // The empty queue — the state this chapter exists to make sense of, and
      // the one a still frame of a full queue would completely fail to show.
      staticValue: 0.72,
      builder: (context, t) => _canvas(_QueuePainter(t: t, palette: palette)),
    );
  }
}

class _QueuePainter extends CustomPainter {
  _QueuePainter({required this.t, required this.palette});

  final double t;
  final _Palette palette;

  static const _slots = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final width = math.min(size.width * 0.46, size.height * 0.62);
    final centreX = size.width * 0.5;
    final top = size.height * 0.10;
    final slotHeight = (size.height * 0.80) / _slots;
    final cardHeight = slotHeight * 0.74;

    Rect slot(int i) => Rect.fromCenter(
      center: Offset(centreX, top + slotHeight * (i + 0.5)),
      width: width,
      height: cardHeight,
    );

    // The empty slots stay drawn the whole way through, so "empty" reads as a
    // queue with room in it rather than as a blank illustration.
    for (var i = 0; i < _slots; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(slot(i), Radius.circular(cardHeight * 0.28)),
        _stroke(palette.faint.withValues(alpha: 0.55), 1.6),
      );
    }

    for (var i = 0; i < _slots; i++) {
      // fill the queue -> review it down to nothing -> one new arrival
      final arrive = Curves.easeOutCubic.transform(
        _seg(t, 0.02 + 0.06 * i, 0.16 + 0.06 * i),
      );
      final leave = Curves.easeInCubic.transform(
        _seg(t, 0.34 + 0.07 * i, 0.46 + 0.07 * i),
      );
      final refill = i == 0
          ? Curves.easeOutCubic.transform(_seg(t, 0.84, 0.96))
          : 0.0;

      // Arrivals drop in from above; reviewed posts leave to the right. The
      // refill is a *fresh* card in a slot that has already been through both,
      // so it has to reset the offsets rather than inherit them — carrying
      // `leave` over is what used to fling the new arrival off the right edge
      // and leave the queue looking permanently empty.
      final double present;
      final double dx;
      final double dy;
      if (refill > 0.01) {
        present = refill;
        dx = 0;
        dy = (1 - refill) * -size.height * 0.35;
      } else {
        present = arrive * (1 - leave);
        dx = leave * size.width * 0.75;
        dy = (1 - arrive) * -size.height * 0.35;
      }
      if (present <= 0.01) continue;

      final body = slot(i).shift(Offset(dx, dy));

      canvas.drawRRect(
        RRect.fromRectAndRadius(body, Radius.circular(cardHeight * 0.28)),
        Paint()..color = palette.accent.withValues(alpha: 0.9 * present),
      );
      final line = _stroke(
        palette.onAccent.withValues(alpha: 0.8 * present),
        math.max(1.5, cardHeight * 0.08),
      );
      for (var k = 0; k < 2; k++) {
        final y = body.center.dy - cardHeight * 0.14 + k * cardHeight * 0.28;
        canvas.drawLine(
          Offset(body.left + width * 0.12, y),
          Offset(body.left + width * (k == 0 ? 0.72 : 0.48), y),
          line,
        );
      }
    }

    // The pause on empty, breathing rather than blank: the queue is waiting on
    // other people, which is a state, not a failure.
    final rest = math.min(_seg(t, 0.60, 0.68), 1 - _seg(t, 0.80, 0.86));
    if (rest > 0) {
      // Two ripples outward from the middle of the empty queue. Not a spinner:
      // nothing is loading, the queue is simply waiting on other people, and a
      // spinner would say the opposite.
      final origin = Offset(centreX, top + slotHeight * (_slots / 2));
      for (var k = 0; k < 2; k++) {
        final p = ((t - 0.60) * 4 + k * 0.5) % 1.0;
        canvas.drawCircle(
          origin,
          width * (0.08 + 0.34 * p),
          _stroke(palette.accent.withValues(alpha: 0.40 * rest * (1 - p)), 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QueuePainter old) => old.t != t || old.palette != palette;
}
