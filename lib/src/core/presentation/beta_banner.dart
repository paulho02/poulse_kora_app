import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';

const _points = [
  (
    Icons.construction_outlined,
    "Relay is in beta. You're using an early version of the app while it's "
        'still being built.',
  ),
  (
    Icons.bug_report_outlined,
    "Bugs and rough edges are expected. If something breaks or feels off, "
        "that's the beta, not you.",
  ),
  (
    Icons.update_outlined,
    'Features can change, move, or disappear between versions as things get '
        'reworked.',
  ),
  (
    Icons.storage_outlined,
    "Data may occasionally be reset while the platform is under active "
        "development — don't treat it as permanent yet.",
  ),
];

/// Slim, permanent strip reminding the user this is a beta build. Unlike
/// [InfoBanner], this never auto-dismisses — it's a standing disclaimer, not
/// a one-off notice.
///
/// Wraps [child] and, when [AppConfig.betaDisclaimerEnabled] is on, renders
/// above it — same spot in `MaterialApp.router`'s `builder` as
/// [OfflineBanner]/[InfoBanner], so it covers every route including
/// login/register, not just the post-login tabs. Toggle it off entirely via
/// `BETA_DISCLAIMER_ENABLED` in `env.json`, e.g. once the app leaves beta.
class BetaBanner extends StatelessWidget {
  const BetaBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.betaDisclaimerEnabled) return child;

    final theme = Theme.of(context);
    final background = theme.colorScheme.tertiaryContainer;
    final foreground = theme.colorScheme.onTertiaryContainer;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // This strip is now the topmost thing on screen, ahead of whatever
      // screen-owned AppBar used to sit directly under the status bar and
      // auto-pick its icon color. Without setting this explicitly the OS
      // keeps whatever style was last set, which reads as invisible
      // (white-on-white) whenever that doesn't match this strip's background.
      value: background.computeLuminance() > 0.5
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Column(
        children: [
          Material(
            color: background,
            // SafeArea *inside* Material, not around it: this way the color
            // still paints all the way to the top of the screen — behind the
            // status bar, same as an AppBar would — and only the tappable
            // content is padded down below the inset. Putting SafeArea
            // outside left the true status-bar area unpainted (showing the
            // stray black window background beneath), so the icon color this
            // picks only matched by coincidence in dark mode.
            child: SafeArea(
              bottom: false,
              child: InkWell(
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  builder: (context) => const _BetaInfoSheet(),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.science_outlined,
                        size: 15,
                        color: foreground,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Beta version — tap for details',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: foreground),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // The strip above already accounted for the status bar, so [child]
          // (a tab's own Scaffold/AppBar, or login/register) must not see
          // that top inset again — otherwise its AppBar adds a second gap.
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _BetaInfoSheet extends StatelessWidget {
  const _BetaInfoSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.science_outlined,
                  size: 26,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Beta version',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            for (final (icon, text) in _points) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(text, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
