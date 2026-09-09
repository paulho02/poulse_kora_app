import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/l10n/generated/app_localizations.dart';
import 'package:poulse_kora_app/src/core/cache/json_cache.dart';
import 'package:poulse_kora_app/src/features/profile/application/profile_providers.dart';
import 'package:poulse_kora_app/src/features/profile/data/profile_repository.dart';
import 'package:poulse_kora_app/src/features/profile/data/user_profile.dart';
import 'package:poulse_kora_app/src/features/profile/presentation/delete_account_dialog.dart';

/// Settings → Delete account, both slides.
///
/// Two things this pins that the copy alone cannot: the *choice* on the first
/// slide reaches the request body (getting it backwards would erase posts
/// somebody meant to keep, irreversibly), and the second slide really does
/// require the password rather than merely showing a field for one.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  UserProfile profileWith({required String authProvider}) => UserProfile(
    id: 'ce1b6b1e-0000-4000-8000-000000000000',
    email: 'ada@example.com',
    username: 'ada',
    bio: null,
    darkMode: false,
    settingsRevision: 0,
    onboardingCompleted: true,
    isVerified: true,
    authProvider: authProvider,
    googleEmail: authProvider == 'google' ? 'ada@example.com' : null,
    profilePictureUrl: null,
  );

  testWidgets('the first slide defaults to the less destructive option', (
    tester,
  ) async {
    // Somebody who taps straight through must not lose their posts by accident:
    // both outcomes are permanent, so the default is the one that destroys less.
    final backend = await _openDialog(tester, profileWith(authProvider: 'password'));
    await tester.tap(find.text(l10n.commonContinue));
    await tester.pumpAndSettle();

    expect(find.text(l10n.deleteAccountSummaryKeepingPosts), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.tap(find.text(l10n.deleteAccountConfirmAction));
    await tester.pumpAndSettle();

    expect(backend.body, {
      'delete_posts': false,
      'current_password': 'hunter2',
    });
  });

  testWidgets('choosing to erase the posts is what the request carries', (
    tester,
  ) async {
    final backend = await _openDialog(tester, profileWith(authProvider: 'password'));
    await tester.tap(find.text(l10n.deleteAccountDeletePostsTitle));
    await tester.pump();
    await tester.tap(find.text(l10n.commonContinue));
    await tester.pumpAndSettle();

    expect(find.text(l10n.deleteAccountSummaryWithPosts), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.tap(find.text(l10n.deleteAccountConfirmAction));
    await tester.pumpAndSettle();

    expect(backend.body!['delete_posts'], true);
  });

  testWidgets('going back keeps the choice that was already made', (
    tester,
  ) async {
    await _openDialog(tester, profileWith(authProvider: 'password'));
    await tester.tap(find.text(l10n.deleteAccountDeletePostsTitle));
    await tester.pump();
    await tester.tap(find.text(l10n.commonContinue));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonBack));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonContinue));
    await tester.pumpAndSettle();

    expect(find.text(l10n.deleteAccountSummaryWithPosts), findsOneWidget);
  });

  testWidgets('an empty password never reaches the server', (tester) async {
    final backend = await _openDialog(tester, profileWith(authProvider: 'password'));
    await tester.tap(find.text(l10n.commonContinue));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.deleteAccountConfirmAction));
    await tester.pumpAndSettle();

    expect(backend.requests, 0);
    expect(find.text(l10n.validationPasswordRequired), findsOneWidget);
  });

  testWidgets('a wrong password is reported under the field', (tester) async {
    final backend = await _openDialog(
      tester,
      profileWith(authProvider: 'password'),
    );
    backend.status = 400;
    await tester.tap(find.text(l10n.commonContinue));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text(l10n.deleteAccountConfirmAction));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorDeleteAccountWrongPassword), findsOneWidget);
    // Still open: a refusal is something to correct, not a reason to start over.
    expect(find.text(l10n.deleteAccountConfirmAction), findsOneWidget);
  });

  testWidgets('a Google account is never asked for a password', (tester) async {
    // Linking overwrote its hash with a random value nobody holds, so a prompt
    // here could only ever be refused.
    final backend = await _openDialog(tester, profileWith(authProvider: 'google'));
    await tester.tap(find.text(l10n.commonContinue));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text(l10n.deleteAccountConfirmAction));
    await tester.pumpAndSettle();

    expect(backend.body, {'delete_posts': false});
  });
}

Future<_FakeBackend> _openDialog(
  WidgetTester tester,
  UserProfile profile,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final backend = _FakeBackend();
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
  dio.httpClientAdapter = backend;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(
          ProfileRepository(dio, JsonCache(prefs)),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDeleteAccountDialog(context, profile),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return backend;
}

class _FakeBackend implements HttpClientAdapter {
  int status = 204;
  int requests = 0;
  Map<String, dynamic>? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path != '/users/me') {
      throw StateError('unexpected request: ${options.path}');
    }
    requests++;
    body = Map<String, dynamic>.from(options.data as Map);
    if (status != 204) {
      return _json({
        'detail': {'error': 'delete_account_wrong_password'},
      }, status: status);
    }
    return _json(null, status: 204);
  }

  static ResponseBody _json(Object? body, {int status = 200}) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          'content-type': ['application/json'],
        },
      );

  @override
  void close({bool force = false}) {}
}
