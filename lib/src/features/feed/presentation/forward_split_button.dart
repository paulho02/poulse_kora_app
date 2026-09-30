import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import 'forwarding_explainer.dart';

/// Forward, with its variants one tap away — the VS Code commit button: the
/// main face does the ordinary thing, and a chevron beside it expands the rest,
/// so the common verdict stays a single tap and the rarer ones don't crowd the
/// footer with buttons of their own.
///
/// The only variant so far is **forward & gift**: the token the review earns
/// goes to the post's author instead of the reader. A gift is praise, which is
/// why it hangs off Forward and never off Drop. Below the variants, always
/// last, a quieter "about forwarding" row opens [showForwardingExplainer] —
/// the segments are one line each, so the explanation lives there instead.
///
/// The variants are not a menu. The chevron *extends the button*: another
/// segment in the same fill, exactly as wide, joined by the same 1px seam that
/// splits off the chevron, with the corners where they meet squared off — so
/// the open button is one shape. A popup surface of any styling (neutral,
/// tinted, bordered) was tried and read as a banner laid over the card; that
/// is why this is an overlay pinned to the button rather than a `MenuAnchor`,
/// which always draws its own surface. It extends downward, or upward where
/// there is no room below (the detail page's pinned footer).
///
/// [onForwardAndGift] null leaves the chevron out entirely rather than
/// offering a segment that can't be used — pass null where a gift can't land
/// (a trust check, whose author is the system). [onForward] null disables
/// every segment, as the card does while a review is in flight.
class ForwardSplitButton extends StatefulWidget {
  const ForwardSplitButton({
    super.key,
    required this.onForward,
    required this.onForwardAndGift,
    this.tonal = false,
    this.compact = false,
  });

  final VoidCallback? onForward;
  final VoidCallback? onForwardAndGift;

  /// Tonal on the feed card (beside the Drop button's outline), filled on the
  /// detail page footer — matching the single buttons this replaced.
  final bool tonal;

  /// Card sizing: smaller icon, tighter padding, shrink-wrapped tap target.
  final bool compact;

  @override
  State<ForwardSplitButton> createState() => _ForwardSplitButtonState();
}

class _ForwardSplitButtonState extends State<ForwardSplitButton>
    with SingleTickerProviderStateMixin {
  // Between every pair of segments, as in VS Code: enough to read as separate
  // targets, not so much that they stop reading as one button.
  static const _seam = 1.0;
  static const _height = 40.0;

  /// The about row is a footnote to the variants, so it is shorter than them.
  static const _aboutHeight = 32.0;

  /// Room the extension needs below the button before it opens upward instead.
  static const _roomNeeded = 96.0;

  final _portal = OverlayPortalController();
  final _link = LayerLink();
  // Created in initState, not lazily: a button that was never opened would
  // otherwise build its controller for the first time in dispose(), when the
  // ticker can no longer look up its TickerMode.
  late final AnimationController _expand;
  bool _upward = false;

  bool get _open => _portal.isShowing;

  @override
  void initState() {
    super.initState();
    _expand = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
  }

  @override
  void didUpdateWidget(ForwardSplitButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A review went in flight (or the gift stopped being possible) while the
    // extension was out: nothing in it can be used any more. Collapsed at once
    // (zero size), and the portal hidden after the frame, since hiding it here
    // would mutate the overlay in the middle of a build.
    if (_open &&
        (widget.onForward == null || widget.onForwardAndGift == null)) {
      _expand.value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _open) setState(_portal.hide);
      });
    }
  }

  @override
  void dispose() {
    _expand.dispose();
    super.dispose();
  }

  void _toggle() => _open ? _close() : _show();

  void _show() {
    final box = context.findRenderObject()! as RenderBox;
    final media = MediaQuery.of(context);
    final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    _upward =
        media.size.height - media.viewPadding.bottom - bottom < _roomNeeded;
    setState(_portal.show);
    _expand.forward(from: 0);
  }

  Future<void> _close({bool animate = true}) async {
    if (animate) await _expand.reverse();
    if (!mounted) return;
    setState(_portal.hide);
  }

  void _gift() {
    _close(animate: false);
    widget.onForwardAndGift?.call();
  }

  void _about() {
    _close(animate: false);
    showForwardingExplainer(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showChevron = widget.onForwardAndGift != null;
    final compact = widget.compact;
    const r = Radius.circular(AppTheme.radius);
    // The corners on the side the extension grows from square off while it
    // is out, so the button and the extension share one outline.
    final top = _open && _upward ? Radius.zero : r;
    final bottom = _open && !_upward ? Radius.zero : r;

    final main = _face(
      borderRadius: BorderRadius.only(
        topLeft: top,
        bottomLeft: bottom,
        topRight: showChevron ? Radius.zero : top,
        bottomRight: showChevron ? Radius.zero : bottom,
      ),
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
      onPressed: widget.onForward,
      child: _SegmentLabel(
        icon: Icons.arrow_forward,
        label: l10n.postForward,
        compact: compact,
      ),
    );

    if (!showChevron) return SizedBox(height: _height, child: main);

    final chevron = SizedBox(
      width: compact ? 34.0 : 44.0,
      child: Tooltip(
        message: l10n.postForwardMoreOptions,
        child: _face(
          borderRadius: BorderRadius.only(topRight: top, bottomRight: bottom),
          padding: EdgeInsets.zero,
          onPressed: widget.onForward == null ? null : _toggle,
          // Pointing the way the extension will go on the next tap.
          child: AnimatedRotation(
            turns: _open ? 0.5 : 0,
            duration: const Duration(milliseconds: 160),
            child: Icon(
              _upward ? Icons.expand_less : Icons.expand_more,
              size: compact ? 18 : 20,
            ),
          ),
        ),
      ),
    );

    // One tap region for the button and its extension: a tap anywhere else
    // folds it back in, a tap on the chevron is left to toggle it.
    return TapRegion(
      groupId: this,
      onTapOutside: (_) {
        if (_open) _close();
      },
      child: CompositedTransformTarget(
        link: _link,
        // A fixed height rather than IntrinsicHeight: the label fitting in
        // `_SegmentLabel` needs a LayoutBuilder, which can't answer intrinsic
        // size queries. 40 is a FilledButton's own height, so the pair still
        // matches Drop beside it.
        child: SizedBox(
          height: _height,
          child: LayoutBuilder(
            builder: (context, constraints) => OverlayPortal(
              controller: _portal,
              overlayChildBuilder: (_) =>
                  _extension(context, constraints.maxWidth),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: main),
                  const SizedBox(width: _seam),
                  chevron,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _extension(BuildContext context, double width) {
    const r = Radius.circular(AppTheme.radius);
    final l10n = AppLocalizations.of(context);
    final enabled = widget.onForward != null;
    // Rounded only on the far edge from the button: the top of the stack when
    // it grows upward, the bottom when it grows downward.
    final farEdge = _upward
        ? const BorderRadius.vertical(top: r)
        : const BorderRadius.vertical(bottom: r);

    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: _upward ? Alignment.topLeft : Alignment.bottomLeft,
      followerAnchor: _upward ? Alignment.bottomLeft : Alignment.topLeft,
      offset: Offset(0, _upward ? -_seam : _seam),
      child: Align(
        alignment: _upward ? Alignment.bottomLeft : Alignment.topLeft,
        child: TapRegion(
          groupId: this,
          child: SizedBox(
            width: width,
            // Unfolds from the edge it is attached to, like the button growing.
            child: SizeTransition(
              sizeFactor: CurvedAnimation(
                parent: _expand,
                curve: Curves.easeOutCubic,
              ),
              alignment: _upward ? Alignment.bottomCenter : Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Segment(
                    tonal: widget.tonal,
                    compact: widget.compact,
                    height: _height,
                    borderRadius: _upward ? farEdge : BorderRadius.zero,
                    onPressed: enabled ? _gift : null,
                    child: _SegmentLabel(
                      icon: Icons.card_giftcard,
                      label: l10n.postForwardAndGift,
                      compact: widget.compact,
                      alignStart: true,
                      gap: 6,
                      // Every row of the stack keeps its icon, so they line up.
                      keepIcon: true,
                    ),
                  ),
                  const SizedBox(height: _seam),
                  // Always last: new variants go above it.
                  _Segment(
                    tonal: widget.tonal,
                    compact: widget.compact,
                    height: _aboutHeight,
                    borderRadius: _upward ? BorderRadius.zero : farEdge,
                    onPressed: enabled ? _about : null,
                    quiet: true,
                    child: _SegmentLabel(
                      icon: Icons.info_outline,
                      label: l10n.postForwardAbout,
                      compact: true,
                      alignStart: true,
                      iconSize: 14,
                      gap: 6,
                      keepIcon: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _face({
    required BorderRadius borderRadius,
    required EdgeInsets padding,
    required VoidCallback? onPressed,
    required Widget child,
  }) {
    final style = FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      padding: padding,
      minimumSize: const Size(0, _height),
      tapTargetSize: widget.compact
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
      // The corners change shape as the extension comes and goes; animating
      // that would lag the extension it is meant to join.
      animationDuration: Duration.zero,
    );
    return widget.tonal
        ? FilledButton.tonal(style: style, onPressed: onPressed, child: child)
        : FilledButton(style: style, onPressed: onPressed, child: child);
  }
}

/// Icon and label on one line, whatever the locale and screen width.
///
/// Every segment is only about half a card wide (less the chevron, for the main
/// face), and German's "Weiterleiten" does not fit there beside an icon on a
/// small phone. Rather than wrap mid-word, it degrades in steps: drop the icon
/// (the label alone still says it), and only if even that is too wide, scale
/// the label down.
class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.icon,
    required this.label,
    required this.compact,
    this.alignStart = false,
    this.iconSize,
    this.gap = 8,
    this.keepIcon = false,
  });

  final IconData icon;
  final String label;
  final bool compact;
  final bool alignStart;
  final double? iconSize;
  final double gap;

  /// Scale the label rather than drop the icon — for the extension's rows,
  /// whose icons line up down the stack and whose ⓘ is what marks the about
  /// row as an explanation rather than another way to forward.
  final bool keepIcon;

  @override
  Widget build(BuildContext context) {
    // The button has already put its label style into DefaultTextStyle, so this
    // measures exactly what will be painted.
    final style = DefaultTextStyle.of(context).style;
    final size = iconSize ?? (compact ? 16.0 : 18.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final withIcon =
            keepIcon || painter.width + gap + size <= constraints.maxWidth;
        painter.dispose();

        final text = Text(label, maxLines: 1, softWrap: false);
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignStart
              ? AlignmentDirectional.centerStart
              : Alignment.center,
          child: withIcon
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: size),
                    SizedBox(width: gap),
                    text,
                  ],
                )
              : text,
        );
      },
    );
  }
}

/// One row of the extension: another segment of the button, in its own fill
/// and text colour — not a card, not a notice. [quiet] is the about row, a
/// size down and a shade fainter than the variants above it.
class _Segment extends StatelessWidget {
  const _Segment({
    required this.tonal,
    required this.compact,
    required this.height,
    required this.borderRadius,
    required this.onPressed,
    required this.child,
    this.quiet = false,
  });

  final bool tonal;
  final bool compact;
  final double height;
  final BorderRadius borderRadius;
  final VoidCallback? onPressed;
  final Widget child;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
      minimumSize: Size(0, height),
      fixedSize: Size.fromHeight(height),
      alignment: AlignmentDirectional.centerStart,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: quiet ? theme.textTheme.labelMedium : null,
    );
    final content = quiet
        ? Builder(
            // The button's own foreground, only fainter.
            builder: (context) {
              final foreground = DefaultTextStyle.of(context).style.color;
              return IconTheme.merge(
                data: IconThemeData(color: foreground?.withValues(alpha: 0.8)),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: foreground?.withValues(alpha: 0.8)),
                  child: child,
                ),
              );
            },
          )
        : child;
    return tonal
        ? FilledButton.tonal(style: style, onPressed: onPressed, child: content)
        : FilledButton(style: style, onPressed: onPressed, child: content);
  }
}
