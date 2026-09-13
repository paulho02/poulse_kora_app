import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/l10n/generated/app_localizations.dart';
import 'package:poulse_kora_app/src/core/cache/cached.dart';
import 'package:poulse_kora_app/src/core/errors/api_exception.dart';
import 'package:poulse_kora_app/src/core/presentation/field_info_icon.dart';
import 'package:poulse_kora_app/src/features/onboarding/presentation/username_step.dart';
import 'package:poulse_kora_app/src/features/profile/application/profile_providers.dart';
import 'package:poulse_kora_app/src/features/profile/data/user_profile.dart';

/// The username field's two pieces of feedback, on the onboarding step (the
/// register form's field is built the same way).
///
/// A name someone else already holds is refused by the backend with
/// `username_taken` (see `app/deps/users.py`) — it used to be an unhandled
/// unique-constraint violation, so the app could only say "something went
/// wrong". The answer names one field, so it belongs under that field rather
/// than in a snackbar the user has to read before it fades. The info icon is
/// the other half: this is the one value on either form that other people see.
void main() {
  final profile = UserProfile(
    id: 'ce1b6b1e-0000-4000-8000-000000000000',
    email: 'ada@example.com',
    username: 'ada',
    bio: null,
    darkMode: false,
    settingsRevision: 0,
    onboardingCompleted: false,
    isVerified: true,
    authProvider: 'google',
    googleEmail: 'ada@example.com',
    profilePictureUrl: null,
    contentLanguages: const ['en', 'de'],
  );

  Future<_FakeProfile> pumpStep(WidgetTester tester, {bool continued = false}) async {
    final notifier = _FakeProfile(profile);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileProvider.overrideWith(() => notifier)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: UsernameStep(initialUsername: 'ada', onContinue: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    return notifier;
  }

  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('a taken username is reported under the field', (tester) async {
    await pumpStep(tester);
    await tester.enterText(find.byType(TextFormField), 'taken');
    await tester.tap(find.text(l10n.commonContinue));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorUsernameTaken), findsOneWidget);
  });

  testWidgets('re-submitting the refused name spends no second request', (
    tester,
  ) async {
    // The server's answer is still true until the text changes, so the form
    // itself blocks the retry.
    final notifier = await pumpStep(tester);
    await tester.enterText(find.byType(TextFormField), 'taken');
    await tester.tap(find.text(l10n.commonContinue));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonContinue));
    await tester.pumpAndSettle();

    expect(notifier.attempts, 1);
  });

  testWidgets('the info icon says who can see the name, on a plain tap', (
    tester,
  ) async {
    // Tap, not long-press: a default Tooltip only opens on a long press on
    // touch devices, which would leave this findable by accident only.
    await pumpStep(tester);
    expect(find.text(l10n.usernameVisibleToOthers), findsNothing);

    await tester.tap(find.byType(FieldInfoIcon));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.usernameVisibleToOthers), findsOneWidget);

    // Let the tooltip's own dismiss timer expire inside the test.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('editing the name clears the refusal', (tester) async {
    await pumpStep(tester);
    await tester.enterText(find.byType(TextFormField), 'taken');
    await tester.tap(find.text(l10n.commonContinue));
    await tester.pumpAndSettle();
    expect(find.text(l10n.errorUsernameTaken), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'taken2');
    await tester.pump();

    expect(find.text(l10n.errorUsernameTaken), findsNothing);
  });
}

class _FakeProfile extends ProfileNotifier {
  _FakeProfile(this.profile);

  final UserProfile profile;
  var attempts = 0;

  @override
  Future<Cached<UserProfile>> build() async => Cached.live(profile);

  @override
  Future<void> updateUsername(String username) async {
    attempts++;
    throw RelayApiException(409, 'username_taken', const {});
  }
}
