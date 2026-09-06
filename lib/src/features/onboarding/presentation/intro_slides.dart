import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/theme/app_colors.dart';

class _Slide {
  const _Slide({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
}

List<_Slide> _slides(AppLocalizations l10n) => [
  _Slide(
    icon: Icons.hub_outlined,
    title: l10n.onboardingSlide1Title,
    body: l10n.onboardingSlide1Body,
  ),
  _Slide(
    icon: Icons.groups_outlined,
    title: l10n.onboardingSlide2Title,
    body: l10n.onboardingSlide2Body,
  ),
  _Slide(
    icon: Icons.token_outlined,
    title: l10n.onboardingSlide3Title,
    body: l10n.onboardingSlide3Body,
  ),
];

/// Skippable intro carousel — the first onboarding step. Three sentences on
/// what Relay is, which is as much as anyone will read before they have seen
/// the app.
///
/// It deliberately does **not** try to teach the model. That is what the
/// tutorial deck offered on the very next step is for
/// (`tutorial_offer_step.dart`), and separating the two is the point: these
/// slides are shown to everyone and so have to stay short, while the deck is
/// asked for and so can take five chapters over it.
///
/// Skipping or finishing both hand off to the same [onDone]; only the slides
/// themselves are optional, never the channel-selection or disclaimer steps
/// that follow.
class IntroSlides extends StatefulWidget {
  const IntroSlides({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<IntroSlides> createState() => _IntroSlidesState();
}

class _IntroSlidesState extends State<IntroSlides> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next(int count) {
    if (_index == count - 1) {
      widget.onDone();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final slides = _slides(l10n);
    final accent = theme.brightness == Brightness.dark
        ? AppColors.accentDark
        : AppColors.accentLight;
    final isLast = _index == slides.length - 1;

    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: TextButton(
                onPressed: widget.onDone,
                child: Text(l10n.onboardingSkip),
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: slides.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final slide = slides[i];
                return LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    // Centred when it fits, scrollable when it doesn't. The
                    // slide used to be a fixed `Column`, which overflowed at
                    // the larger text sizes — on the first screen a new
                    // account ever sees.
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _SlideBadge(
                            icon: slide.icon,
                            accent: accent,
                            // Restarts the entrance on every page change, so
                            // the badge arrives with its slide instead of
                            // sitting there as a fixed decoration behind
                            // swapping text.
                            active: i == _index,
                          ),
                          const SizedBox(height: 32),
                          Text(
                            slide.title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            slide.body,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              slides.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == _index ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _index
                      ? accent
                      : theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _next(slides.length),
                // "Continue", not "Get started": the last slide now hands off
                // to the tutorial offer rather than into the app, and a button
                // that promises the feed and delivers another question is a
                // small lie the very first screen does not need.
                child: Text(
                  isLast ? l10n.commonContinue : l10n.onboardingNext,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The slide's icon, in its disc, with two pieces of motion: the disc scales
/// and fades in as the slide arrives, and a ring breathes behind it while the
/// slide is on screen.
///
/// It is small on purpose. The deck next door does the real explaining with
/// real diagrams; this only has to keep three static screens from reading as a
/// PDF, and anything more elaborate here would make the tutorial's own
/// animations look like more of the same.
class _SlideBadge extends StatefulWidget {
  const _SlideBadge({
    required this.icon,
    required this.accent,
    required this.active,
  });

  final IconData icon;
  final Color accent;
  final bool active;

  @override
  State<_SlideBadge> createState() => _SlideBadgeState();
}

class _SlideBadgeState extends State<_SlideBadge>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.active ? 0 : 1,
  );
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  var _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(covariant _SlideBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    if (_reduceMotion) {
      _entrance.value = 1;
      _breath.stop();
      return;
    }
    if (widget.active) {
      _entrance.forward(from: 0);
      if (!_breath.isAnimating) _breath.repeat();
    } else {
      _breath.stop();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      height: 148,
      child: AnimatedBuilder(
        animation: Listenable.merge([_entrance, _breath]),
        builder: (context, child) {
          final settle = Curves.easeOutBack.transform(
            _entrance.value.clamp(0.0, 1.0),
          );
          final breath = 0.5 + 0.5 * math.sin(_breath.value * 2 * math.pi);
          return Opacity(
            opacity: _entrance.value.clamp(0.0, 1.0),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 120 + 22 * breath,
                  height: 120 + 22 * breath,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.accent.withValues(
                        alpha: 0.22 * (1 - breath),
                      ),
                    ),
                  ),
                ),
                Transform.scale(scale: 0.7 + 0.3 * settle, child: child),
              ],
            ),
          );
        },
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(widget.icon, size: 56, color: widget.accent),
        ),
      ),
    );
  }
}
