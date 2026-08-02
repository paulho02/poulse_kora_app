import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/error_state_view.dart';
import '../../profile/application/profile_providers.dart';
import 'channel_selection_step.dart';
import 'disclaimer_step.dart';
import 'intro_slides.dart';

enum _OnboardingStep { intro, channels, disclaimer }

/// One-time flow shown right after registration (see the `/onboarding`
/// redirect in `routing/app_router.dart`, driven by
/// `UserProfile.onboardingCompleted`). Three steps in a single screen rather
/// than three routes: the step index is transient flow state, not something
/// that needs to survive a deep link or a back-button press independently.
///
/// Also reused, via [isReplay], as an already-onboarded user's "watch the
/// intro again" from Settings (`/onboarding/replay`, a normal pushed route
/// rather than the redirect-driven one) — see `settings_screen.dart`'s
/// "Replay intro" row.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.isReplay = false});

  /// True when reached from Settings rather than the mandatory post-
  /// registration flow. Skips channel selection (those channels are already
  /// chosen) and, on confirming the disclaimer, just pops back to Settings
  /// instead of calling `completeOnboarding()` again.
  final bool isReplay;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  var _step = _OnboardingStep.intro;
  var _submitting = false;

  Future<void> _confirmDisclaimer() async {
    if (widget.isReplay) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(profileProvider.notifier).completeOnboarding();
      // No explicit navigation: the router's redirect watches `profileProvider`
      // and takes over as soon as `onboardingCompleted` flips to true.
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_step) {
        _OnboardingStep.intro => IntroSlides(
          onDone: () => setState(
            () => _step = widget.isReplay
                ? _OnboardingStep.disclaimer
                : _OnboardingStep.channels,
          ),
        ),
        _OnboardingStep.channels => ChannelSelectionStep(
          onContinue: () => setState(() => _step = _OnboardingStep.disclaimer),
        ),
        _OnboardingStep.disclaimer => DisclaimerStep(
          onConfirm: _confirmDisclaimer,
          isSubmitting: _submitting,
        ),
      },
    );
  }
}
