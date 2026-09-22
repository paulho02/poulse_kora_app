import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../channels/application/channels_providers.dart';
import '../../profile/application/profile_providers.dart';
import '../../tutorial/presentation/tutorial_deck.dart';
import 'channel_selection_step.dart';
import 'content_languages_step.dart';
import 'disclaimer_step.dart';
import 'intro_slides.dart';
import 'tutorial_offer_step.dart';
import 'username_step.dart';

enum _OnboardingStep {
  intro,
  tutorialOffer,
  tutorial,
  username,
  channels,
  languages,
  disclaimer,
}

/// One-time flow shown right after registration (see the `/onboarding`
/// redirect in `routing/app_router.dart`, driven by
/// `UserProfile.onboardingCompleted`). The steps live in a single screen rather
/// than in separate routes: the step index is transient flow state, not
/// something that needs to survive a deep link or a back-button press
/// independently.
///
/// Two of the seven steps are conditional:
///
/// - The **username** step is only reached by Google signups, because only
///   they never got asked for one (the register form asks; Google has no such
///   field, so the backend derived one). See [_stepAfterOffer].
/// - The **tutorial** step is reached only by accepting the offer before it.
///   It is the same [TutorialDeck] Settings opens at `/tutorial`, embedded
///   rather than pushed — while `onboardingCompleted` is false the router's
///   gate chain bounces every other route back to `/onboarding`, so a pushed
///   route could not survive here.
///
/// Also reused, via [isReplay], as an already-onboarded user's "watch the
/// intro again" from Settings (`/onboarding/replay`, a normal pushed route
/// rather than the redirect-driven one) — see `settings_screen.dart`'s
/// "Replay intro" row. A replay skips the tutorial offer: Settings lists the
/// tutorial as its own row two lines away, and offering it again mid-replay
/// would be a second door to a room the reader is already standing outside.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.isReplay = false});

  /// True when reached from Settings rather than the mandatory post-
  /// registration flow. Skips channel and language selection (both are already
  /// chosen, and both have a permanent home in the Filters tab) and, on
  /// confirming the disclaimer, just pops back to Settings instead of calling
  /// `completeOnboarding()` again.
  final bool isReplay;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  var _step = _OnboardingStep.intro;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.isReplay) return;
    // Fetch the channel list now, not when `ChannelSelectionStep` mounts.
    //
    // Nothing else in this flow watches `channelsNotifierProvider`, so the
    // step used to be what started the request, and the step is several
    // minutes downstream of here for anyone who takes the tutorial. That put
    // the one request onboarding cannot continue without at the end of a long
    // idle gap, on an account too new to have a cached list to fall back on:
    // a single dropped connection left a dead end that only the Retry button
    // could clear. Asking now puts it right after the register call, while the
    // connection has just demonstrably worked, and a later drop then costs
    // nothing because the list is already in hand.
    //
    // `ignore()` because a failure here is not this screen's to report: the
    // step re-asks when it mounts, and shows the error itself if that fails
    // too.
    ref.read(channelsNotifierProvider.future).ignore();
  }

  /// Where the intro hands off. A replay goes straight to the disclaimer
  /// (channels and languages are long since chosen, the username is not being
  /// re-confirmed, and the tutorial has its own Settings row); a first run is
  /// offered the tutorial.
  _OnboardingStep _stepAfterIntro() => widget.isReplay
      ? _OnboardingStep.disclaimer
      : _OnboardingStep.tutorialOffer;

  /// Where both answers to the tutorial offer converge, and where the deck
  /// returns to. A Google account confirms its derived username first; a
  /// password account already typed one on the register form, so re-asking
  /// would be busywork.
  _OnboardingStep _stepAfterOffer() {
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: switch (_step) {
        _OnboardingStep.intro => IntroSlides(
          onDone: () => setState(() => _step = _stepAfterIntro()),
        ),
        _OnboardingStep.tutorialOffer => TutorialOfferStep(
          onAccept: () => setState(() => _step = _OnboardingStep.tutorial),
          onDecline: () => setState(() => _step = _stepAfterOffer()),
        ),
        _OnboardingStep.tutorial => TutorialDeck(
          onFinish: () => setState(() => _step = _stepAfterOffer()),
          onSkip: () => setState(() => _step = _stepAfterOffer()),
          footnote: l10n.tutorialSettingsHint,
        ),
        _OnboardingStep.username => UsernameStep(
          initialUsername:
              ref.watch(profileProvider).value?.data.username ?? '',
          onContinue: () => setState(() => _step = _OnboardingStep.channels),
        ),
        _OnboardingStep.channels => ChannelSelectionStep(
          onContinue: () => setState(() => _step = _OnboardingStep.languages),
        ),
        _OnboardingStep.languages => ContentLanguagesStep(
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
