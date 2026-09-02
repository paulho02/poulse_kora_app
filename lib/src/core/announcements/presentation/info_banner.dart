import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../application/announcement_providers.dart';
import '../data/announcement.dart';

/// A floating, push-notification-style card for an announcement pushed by the
/// app owner (e.g. a maintenance notice), fetched on start.
///
/// Deliberately overlaid via [Stack] rather than pushed into the layout like
/// `OfflineBanner` — a notification should sit on top of the app for a moment,
/// not permanently resize it. Mounted in `MaterialApp.router`'s `builder`
/// alongside `OfflineBanner`, so it covers every route including
/// login/register — the GET it depends on is public and answered pre-login too.
class InfoBanner extends ConsumerStatefulWidget {
  const InfoBanner({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<InfoBanner> createState() => _InfoBannerState();
}

class _InfoBannerState extends ConsumerState<InfoBanner> {
  bool _dontShowAgain = false;

  // Kept after dismissal so the exit animation slides the card that was
  // actually on screen away, instead of the content going blank the instant
  // `visibleAnnouncementProvider` flips to null.
  Announcement? _lastShown;

  @override
  Widget build(BuildContext context) {
    final announcement = ref.watch(visibleAnnouncementProvider);
    if (announcement != null) _lastShown = announcement;
    final visible = announcement != null;
    final shown = announcement ?? _lastShown;

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (shown != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 220),
                    curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
                    // Fractional, not fixed pixels, so it clears the card
                    // regardless of how many lines the message wraps to.
                    offset: visible ? Offset.zero : const Offset(0, -1.5),
                    child: AnimatedOpacity(
                      key: const Key('infoBannerOpacity'),
                      duration: const Duration(milliseconds: 180),
                      opacity: visible ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !visible,
                        child: _Card(
                          announcement: shown,
                          dontShowAgain: _dontShowAgain,
                          onDontShowAgainChanged: (v) =>
                              setState(() => _dontShowAgain = v),
                          onClose: () => _dismiss(shown.id),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _dismiss(String id) {
    // The "x" always takes effect for the rest of this session...
    ref.read(announcementSessionDismissalProvider.notifier).dismiss(id);
    // ...and additionally persists forever if the box was checked at the
    // moment of closing.
    if (_dontShowAgain) {
      ref
          .read(announcementForeverDismissalProvider.notifier)
          .dismissForever(id);
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.announcement,
    required this.dontShowAgain,
    required this.onDontShowAgainChanged,
    required this.onClose,
  });

  final Announcement announcement;
  final bool dontShowAgain;
  final ValueChanged<bool> onDontShowAgainChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // The Material 3 token pair meant for exactly this — a floating surface
    // that reads as an overlay, not another panel blending into the app,
    // in both light and dark theme.
    final background = theme.colorScheme.inverseSurface;
    final foreground = theme.colorScheme.onInverseSurface;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Material(
        color: background,
        elevation: 6,
        shadowColor: Colors.black,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.campaign_rounded, size: 20, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        announcement.message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: foreground,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () => onDontShowAgainChanged(!dontShowAgain),
                      borderRadius: BorderRadius.circular(6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 22,
                            width: 22,
                            child: Checkbox(
                              value: dontShowAgain,
                              onChanged: (v) =>
                                  onDontShowAgainChanged(v ?? false),
                              visualDensity: VisualDensity.compact,
                              activeColor: foreground,
                              checkColor: background,
                              side: BorderSide(
                                color: foreground.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n.infoBannerDontShowAgain,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: foreground.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // No `tooltip` here: IconButton wraps a non-null tooltip in a
              // `Tooltip`, which needs an ancestor `Overlay` — but this card
              // is mounted in `MaterialApp.router`'s `builder`, outside the
              // Navigator that owns the only `Overlay` in this tree, so that
              // would throw "No Overlay widget found" the moment it builds.
              Semantics(
                label: l10n.infoBannerDismiss,
                child: IconButton(
                  icon: Icon(Icons.close, size: 18, color: foreground),
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
