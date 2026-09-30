import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/core/app_config/application/app_config_providers.dart';
import 'package:peerkola/src/core/app_config/data/public_app_config.dart';
import 'package:peerkola/src/features/auth/application/auth_providers.dart';
import 'package:peerkola/src/features/auth/data/auth_repository.dart';
import 'package:peerkola/src/features/auth/presentation/forgot_password_screen.dart';

/// The "forgot password" flow: request a code, then redeem it for a new
/// password. Both backend routes answer identically whether or not the email
/// exists (see backend/app/api/password_reset.py), so there is nothing to pin
/// about that here - this only covers what the screen itself is responsible
/// for: advancing to the code step, catching an empty email or mismatched
/// passwords locally, surfacing a backend refusal without losing what was
/// typed, and returning to login on success.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('submitting the email advances to the code step', (tester) async {
    final harness = await _pump(tester);

    await tester.enterText(find.byType(TextFormField).first, 'ada@example.com');
    await tester.tap(find.text(l10n.forgotPasswordSendCode));
    await tester.pumpAndSettle();

    expect(harness.backend.forgotPasswordRequests, 1);
    expect(harness.backend.forgotPasswordBody, {'email': 'ada@example.com'});
    expect(find.text(l10n.forgotPasswordRequestSentSnackbar), findsOneWidget);
    expect(find.text(l10n.forgotPasswordCodeLabel), findsOneWidget);
  });

  testWidgets('an empty email is never submitted', (tester) async {
    final harness = await _pump(tester);

    await tester.tap(find.text(l10n.forgotPasswordSendCode));
    await tester.pumpAndSettle();

    expect(harness.backend.forgotPasswordRequests, 0);
    expect(find.text(l10n.validationEmailRequired), findsOneWidget);
  });

  testWidgets('mismatched new passwords are caught before the request', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _advanceToCodeStep(tester, l10n);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '482913');
    await tester.enterText(fields.at(1), 'brand-new-pw-1');
    await tester.enterText(fields.at(2), 'does-not-match');
    await tester.tap(find.text(l10n.forgotPasswordResetButton));
    await tester.pumpAndSettle();

    expect(harness.backend.resetRequests, 0);
    expect(find.text(l10n.validationPasswordsDoNotMatch), findsOneWidget);
  });

  testWidgets('a wrong code is reported without losing the typed password', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _advanceToCodeStep(tester, l10n);
    harness.backend.resetError = 'password_reset_invalid_or_expired_code';

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '000000');
    await tester.enterText(fields.at(1), 'brand-new-pw-1');
    await tester.enterText(fields.at(2), 'brand-new-pw-1');
    await tester.tap(find.text(l10n.forgotPasswordResetButton));
    await tester.pumpAndSettle();

    expect(harness.backend.resetRequests, 1);
    expect(find.text(l10n.errorInvalidCodeGeneric), findsOneWidget);
    // Still on the code step with the password intact - a refusal is
    // something to correct, not a reason to start over.
    expect(find.text(l10n.forgotPasswordResetButton), findsOneWidget);
    // Both the new-password and confirm fields, still filled in.
    expect(find.text('brand-new-pw-1'), findsNWidgets(2));
  });

  testWidgets('a successful reset returns to the login screen', (tester) async {
    final harness = await _pump(tester);
    await _advanceToCodeStep(tester, l10n);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '482913');
    await tester.enterText(fields.at(1), 'brand-new-pw-1');
    await tester.enterText(fields.at(2), 'brand-new-pw-1');
    await tester.tap(find.text(l10n.forgotPasswordResetButton));
    await tester.pumpAndSettle();

    expect(harness.backend.resetBody, {
      'email': 'ada@example.com',
      'code': '482913',
      'new_password': 'brand-new-pw-1',
    });
    expect(find.text('login screen'), findsOneWidget);
  });
}

Future<void> _advanceToCodeStep(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await tester.enterText(find.byType(TextFormField).first, 'ada@example.com');
  await tester.tap(find.text(l10n.forgotPasswordSendCode));
  await tester.pumpAndSettle();
}

class _Harness {
  final backend = _FakeBackend();
}

Future<_Harness> _pump(WidgetTester tester) async {
  final harness = _Harness();
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
  dio.httpClientAdapter = harness.backend;

  final router = GoRouter(
    initialLocation: '/forgot-password',
    routes: [
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('login screen'))),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(AuthRepository(dio)),
        appConfigProvider.overrideWith(
          (ref) async => const PublicAppConfig(
            requireEmailVerification: false,
            requireStrongPassword: false,
            passwordMinLength: 1,
            passwordMinCharacterClasses: 1,
            emailVerificationResendCooldownSeconds: 60,
            googleOauthEnabled: false,
            contentLanguages: ['en', 'de'],
            languageUnspecified: 'und',
          ),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

class _FakeBackend implements HttpClientAdapter {
  int forgotPasswordRequests = 0;
  int resetRequests = 0;
  Map<String, dynamic>? forgotPasswordBody;
  Map<String, dynamic>? resetBody;
  String? resetError;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/auth/forgot-password') {
      forgotPasswordRequests++;
      forgotPasswordBody = Map<String, dynamic>.from(options.data as Map);
      return _json({'msg': 'ok'});
    }
    if (options.path == '/auth/reset-password/confirm') {
      resetRequests++;
      resetBody = Map<String, dynamic>.from(options.data as Map);
      final error = resetError;
      if (error != null) {
        return _json({
          'detail': {'error': error},
        }, status: 400);
      }
      return ResponseBody.fromString('', 204);
    }
    throw StateError('unexpected request: ${options.path}');
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
