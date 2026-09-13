import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/l10n/generated/app_localizations.dart';
import 'package:poulse_kora_app/src/core/cache/cached.dart';
import 'package:poulse_kora_app/src/core/errors/api_exception.dart';
import 'package:poulse_kora_app/src/core/presentation/error_state_view.dart';
import 'package:poulse_kora_app/src/features/channels/application/channels_providers.dart';
import 'package:poulse_kora_app/src/features/channels/data/channel.dart';
import 'package:poulse_kora_app/src/features/onboarding/presentation/channel_selection_step.dart';
import 'package:poulse_kora_app/src/features/onboarding/presentation/onboarding_screen.dart';

/// Onboarding cannot continue without the channel list, and a brand-new account
/// has no cached copy to fall back on. One dropped connection therefore used to
/// end the flow at a Retry button, and the window for that drop is now several
/// minutes wide, because the tutorial sits in front of this step.
///
/// The fix has two halves and both are pinned here: fetch the list when the
/// flow *starts*, and re-ask at the step if that fetch failed, since by then
/// its error is minutes old and was never on screen.
void main() {
  /// A container with auto-retry off, matching `main.dart`'s `_retryPolicy` for
  /// a connectivity failure. Without this the test would measure Riverpod's ten
  /// built-in retries instead of the app's own behaviour, and would pass for
  /// the wrong reason.
  ProviderContainer containerFor(_FakeChannels notifier) {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [channelsNotifierProvider.overrideWith(() => notifier)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpIn(
    WidgetTester tester,
    ProviderContainer container,
    Widget child,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
    // Not `pumpAndSettle`: the intro slides' icon badge and the tutorial's
    // illustrations both animate on a loop, so nothing on this flow ever
    // settles. Two pumps are enough to drain the microtasks a refresh queues.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The warm-up `OnboardingScreen` runs, played out before the step mounts.
  Future<void> warmUp(ProviderContainer container) async {
    await container
        .read(channelsNotifierProvider.future)
        .then((_) {}, onError: (_, _) {});
  }

  group('ChannelSelectionStep', () {
    testWidgets('re-asks when it arrives on a warm-up that failed', (
      tester,
    ) async {
      final notifier = _FakeChannels(failFirst: true);
      final container = containerFor(notifier);
      await warmUp(container);
      expect(notifier.fetches, 1);
      expect(container.read(channelsNotifierProvider).hasError, isTrue);

      await pumpIn(
        tester,
        container,
        Scaffold(body: ChannelSelectionStep(onContinue: () {})),
      );

      expect(notifier.fetches, 2, reason: 'the stale error should be re-asked');
      expect(find.text('Technology'), findsOneWidget);
      expect(find.byType(ErrorStateView), findsNothing);
    });

    testWidgets('leaves a warm-up that worked alone', (tester) async {
      // Refreshing a good list would put a spinner in front of everyone to fix
      // a problem nobody had.
      final notifier = _FakeChannels();
      final container = containerFor(notifier);
      await warmUp(container);

      await pumpIn(
        tester,
        container,
        Scaffold(body: ChannelSelectionStep(onContinue: () {})),
      );

      expect(notifier.fetches, 1);
      expect(find.text('Technology'), findsOneWidget);
    });

    testWidgets('shows a second failure, with a way to try again', (
      tester,
    ) async {
      final notifier = _FakeChannels(failAlways: true);
      final container = containerFor(notifier);
      await warmUp(container);

      await pumpIn(
        tester,
        container,
        Scaffold(body: ChannelSelectionStep(onContinue: () {})),
      );

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(notifier.fetches, 2);
      expect(find.byType(ErrorStateView), findsOneWidget);

      await tester.tap(find.text(l10n.errorStateTryAgain));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(notifier.fetches, 3);
    });
  });

  group('OnboardingScreen', () {
    testWidgets('fetches the channel list on the very first step', (
      tester,
    ) async {
      final notifier = _FakeChannels();
      final container = containerFor(notifier);

      await pumpIn(tester, container, const OnboardingScreen());

      // Still on the intro slides, and the list is already in hand.
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.onboardingSlide1Title), findsOneWidget);
      expect(notifier.fetches, 1);
    });

    testWidgets('a replay does not, since it never reaches the step', (
      tester,
    ) async {
      final notifier = _FakeChannels();
      final container = containerFor(notifier);

      await pumpIn(tester, container, const OnboardingScreen(isReplay: true));

      expect(notifier.fetches, 0);
    });
  });
}

/// Stands in for the real notifier so fetches can be counted. `failFirst`
/// models the warm-up that dropped; `failAlways` models a connection that is
/// genuinely down rather than blipped.
class _FakeChannels extends ChannelsNotifier {
  _FakeChannels({this.failFirst = false, this.failAlways = false});

  final bool failFirst;
  final bool failAlways;
  int fetches = 0;

  Future<Cached<List<Channel>>> _fetch() async {
    fetches++;
    if (failAlways || (failFirst && fetches == 1)) {
      throw RelayApiException(
        0,
        'offline',
        const {},
        kind: ApiErrorKind.offline,
      );
    }
    return Cached.live([
      Channel(
        id: 1,
        name: 'Technology',
        color: '#2563EB',
        description: 'Tech talk',
        isSubscribed: false,
        postPriceMin: 3,
      postPriceMax: 3,
      ),
    ]);
  }

  @override
  Future<Cached<List<Channel>>> build() => _fetch();

  @override
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}
