import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/error_state_view.dart';
import '../../profile/application/profile_providers.dart';
import 'channel_selection_step.dart';
import 'disclaimer_step.dart';
import 'intro_slides.dart';
import 'username_step.dart';

enum _OnboardingStep { intro, username, channels, disclaimer }

/// One-time flow shown right after registration (see the `/onboarding`
/// redirect in `routing/app_router.dart`, driven by
/// `UserProfile.onboardingCompleted`). The steps live in a single screen rather
/// than in separate routes: the step index is transient flow state, not
/// something that needs to survive a deep link or a back-button press
/// independently.
///
/// The username step is conditional - only Google signups reach it, because
/// only they never got asked for a username (the register form asks; Google has
/// no such field, so the backend derived one). See [_stepAfterIntro].
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

  /// Where the intro hands off, which depends on why we are here.
  ///
  /// Replay skips straight to the disclaimer (channels are long since chosen,
  /// and the username is not being re-confirmed). Otherwise a Google account
  /// confirms its derived username first; a password account already typed one
  /// on the register form, so re-asking would be busywork.
  _OnboardingStep _stepAfterIntro() {
    if (widget.isReplay) return _OnboardingStep.disclaimer;
    final profile = ref.read(profileProvider).value?.data;
    if (profile != null && profile.isGoogleAccount) {
      return _OnboardingStep.username;
    }
    return _OnboardingStep.channels;
  }

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
          onDone: () => setState(() => _step = _stepAfterIntro()),
        ),
        _OnboardingStep.username => UsernameStep(
          initialUsername:
              ref.watch(profileProvider).value?.data.username ?? '',
          onContinue: () => setState(() => _step = _OnboardingStep.channels),
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
