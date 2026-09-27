import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/features/auth/application/auth_providers.dart';
import 'package:peerkola/src/features/auth/data/auth_repository.dart';
import 'package:peerkola/src/features/profile/data/user_profile.dart';
import 'package:peerkola/src/features/profile/presentation/link_google_dialog.dart';

/// Settings → Connect Google.
///
/// The backend refuses to link without the current password (linking destroys
/// it, so a stolen token alone must not be enough). This pins that the dialog
/// really collects it, sends it alongside the Google token, and keeps a refusal
/// in front of the user instead of closing on them.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('the password travels with the Google token', (tester) async {
    final harness = await _openDialog(tester);
    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.tap(find.text(l10n.authLinkGoogleConfirm));
    await tester.pumpAndSettle();

    expect(harness.backend.body, {
      'id_token': 'google-token',
      'current_password': 'hunter2',
    });
    expect(harness.result, isTrue);
    expect(find.text(l10n.authLinkGoogleConfirm), findsNothing);
  });

  testWidgets('an empty password never reaches Google or the server', (
    tester,
  ) async {
    final harness = await _openDialog(tester);
    await tester.tap(find.text(l10n.authLinkGoogleConfirm));
    await tester.pumpAndSettle();

    expect(harness.pickerOpened, 0);
    expect(harness.backend.requests, 0);
    expect(find.text(l10n.validationPasswordRequired), findsOneWidget);
  });

  testWidgets('a wrong password is reported under the field', (tester) async {
    final harness = await _openDialog(tester);
    harness.backend.error = 'google_link_wrong_password';
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text(l10n.authLinkGoogleConfirm));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorGoogleLinkWrongPassword), findsOneWidget);
    // Still open: a refusal is something to correct, not a reason to start over.
    expect(find.text(l10n.authLinkGoogleConfirm), findsOneWidget);
    expect(harness.result, isNull);
  });

  testWidgets('dismissing the Google picker leaves the dialog as it was', (
    tester,
  ) async {
    final harness = await _openDialog(tester, idToken: null);
    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.tap(find.text(l10n.authLinkGoogleConfirm));
    await tester.pumpAndSettle();

    expect(harness.pickerOpened, 1);
    expect(harness.backend.requests, 0);
    expect(find.text(l10n.authLinkGoogleConfirm), findsOneWidget);
    expect(find.text('hunter2'), findsOneWidget);
  });

  testWidgets('cancel links nothing', (tester) async {
    final harness = await _openDialog(tester);
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(harness.result, isFalse);
    expect(harness.backend.requests, 0);
  });
}

class _Harness {
  final backend = _FakeBackend();
  int pickerOpened = 0;
  bool? result;
}

Future<_Harness> _openDialog(
  WidgetTester tester, {
  String? idToken = 'google-token',
}) async {
  final harness = _Harness();
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
  dio.httpClientAdapter = harness.backend;
  final profile = UserProfile(
    id: 'ce1b6b1e-0000-4000-8000-000000000000',
    email: 'ada@example.com',
    username: 'ada',
    bio: null,
    darkMode: false,
    settingsRevision: 0,
    onboardingCompleted: true,
    isVerified: true,
    authProvider: 'password',
    googleEmail: null,
    profilePictureUrl: null,
    contentLanguages: const ['en', 'de'],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(AuthRepository(dio)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                harness.result = await showLinkGoogleDialog(
                  context,
                  profile,
                  obtainIdToken: () async {
                    harness.pickerOpened++;
                    return idToken;
                  },
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return harness;
}

class _FakeBackend implements HttpClientAdapter {
  String? error;
  int requests = 0;
  Map<String, dynamic>? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path != '/auth/google/link') {
      throw StateError('unexpected request: ${options.path}');
    }
    requests++;
    body = Map<String, dynamic>.from(options.data as Map);
    final error = this.error;
    if (error != null) {
      return _json({
        'detail': {'error': error},
      }, status: 400);
    }
    return _json({});
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
