import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:peerkola/src/features/auth/data/google_sign_in_service.dart';

/// Covers the two things that made a fresh install's first Google sign-in fail
/// until the user had tapped the button a few times: transient Play-services
/// errors surfacing as a hard failure, and a failed `initialize()` being
/// remembered as the answer.
///
/// `GoogleSignIn` has a private constructor, so the plugin itself cannot be
/// faked — these exercise the retry policy directly, which is where the
/// decision lives.
void main() {
  GoogleSignInException failure(GoogleSignInExceptionCode code) =>
      GoogleSignInException(code: code);

  // No real waiting: every test here would otherwise pay the backoff.
  const noBackoff = Duration.zero;

  group('isTransientGoogleSignInError', () {
    test('retries the two codes that carry no verdict', () {
      expect(
        isTransientGoogleSignInError(GoogleSignInExceptionCode.interrupted),
        isTrue,
      );
      expect(
        isTransientGoogleSignInError(GoogleSignInExceptionCode.unknownError),
        isTrue,
      );
    });

    test('treats a decision or a misconfiguration as permanent', () {
      for (final code in [
        GoogleSignInExceptionCode.canceled,
        GoogleSignInExceptionCode.clientConfigurationError,
        GoogleSignInExceptionCode.providerConfigurationError,
        GoogleSignInExceptionCode.uiUnavailable,
        GoogleSignInExceptionCode.userMismatch,
      ]) {
        expect(isTransientGoogleSignInError(code), isFalse, reason: '$code');
      }
    });
  });

  group('retryTransientGoogleSignIn', () {
    test('succeeds on a later attempt without surfacing the failures', () async {
      var calls = 0;
      final result = await retryTransientGoogleSignIn(() async {
        calls++;
        if (calls < 3) throw failure(GoogleSignInExceptionCode.unknownError);
        return 'id-token';
      }, backoff: noBackoff);

      expect(result, 'id-token');
      expect(calls, 3);
    });

    test('stops at maxAttempts and rethrows the last failure', () async {
      var calls = 0;
      await expectLater(
        retryTransientGoogleSignIn(() async {
          calls++;
          throw failure(GoogleSignInExceptionCode.interrupted);
        }, backoff: noBackoff),
        throwsA(
          isA<GoogleSignInException>().having(
            (e) => e.code,
            'code',
            GoogleSignInExceptionCode.interrupted,
          ),
        ),
      );
      expect(calls, 3);
    });

    test('never re-prompts after the user backs out', () async {
      // `signIn` maps `canceled` to null before this sees it, but the policy
      // must not be the thing that re-opens the account picker either way.
      var calls = 0;
      await expectLater(
        retryTransientGoogleSignIn(() async {
          calls++;
          throw failure(GoogleSignInExceptionCode.canceled);
        }, backoff: noBackoff),
        throwsA(isA<GoogleSignInException>()),
      );
      expect(calls, 1);
    });

    test('does not retry a misconfigured build', () async {
      var calls = 0;
      await expectLater(
        retryTransientGoogleSignIn(() async {
          calls++;
          throw failure(GoogleSignInExceptionCode.clientConfigurationError);
        }, backoff: noBackoff),
        throwsA(isA<GoogleSignInException>()),
      );
      expect(calls, 1);
    });

    test('leaves anything that is not a plugin error alone', () async {
      var calls = 0;
      await expectLater(
        retryTransientGoogleSignIn(() async {
          calls++;
          throw StateError('not the plugin');
        }, backoff: noBackoff),
        throwsA(isA<StateError>()),
      );
      expect(calls, 1);
    });

    test('returns null through, since that is "user backed out"', () async {
      var calls = 0;
      final result = await retryTransientGoogleSignIn<String?>(() async {
        calls++;
        return null;
      }, backoff: noBackoff);

      expect(result, isNull);
      expect(calls, 1);
    });
  });
}
