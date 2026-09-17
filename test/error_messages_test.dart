import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/l10n/generated/app_localizations.dart';
import 'package:poulse_kora_app/src/core/errors/api_exception.dart';
import 'package:poulse_kora_app/src/core/errors/error_messages.dart';

void main() {
  final req = RequestOptions(path: '/posts/feed');
  final en = lookupAppLocalizations(const Locale('en'));
  final de = lookupAppLocalizations(const Locale('de'));

  group('asRelayException', () {
    test('unwraps the failure the interceptor tucked into DioException.error', () {
      // Regression: Dio rethrows its own type, so `AsyncValue.guard` hands the
      // widget a DioException, not the RelayApiException inside it. Before this
      // was unwrapped, every offline screen read "Something went wrong".
      final inner = RelayApiException(
        0,
        'offline',
        const {},
        kind: ApiErrorKind.offline,
      );
      final wrapped = DioException(requestOptions: req, error: inner);

      final result = asRelayException(wrapped);
      expect(result.error, 'offline');
      expect(result.isConnectivityFailure, isTrue);
    });

    test('classifies a bare connection error as offline', () {
      final e = DioException(
        requestOptions: req,
        type: DioExceptionType.connectionError,
      );
      expect(asRelayException(e).kind, ApiErrorKind.offline);
    });

    test('treats a response-less unknown failure as offline', () {
      // Browsers hide the reason for a failed fetch, so Dio reports `unknown`.
      final e = DioException(
        requestOptions: req,
        type: DioExceptionType.unknown,
      );
      expect(asRelayException(e).kind, ApiErrorKind.offline);
    });

    test('reads the structured error code out of a 4xx body', () {
      final e = DioException(
        requestOptions: req,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: req,
          statusCode: 402,
          data: {
            'detail': {
              'error': 'insufficient_tokens',
              'price': 5,
              'balance': 2,
            },
          },
        ),
      );
      final result = asRelayException(e);
      expect(result.error, 'insufficient_tokens');
      expect(result.kind, ApiErrorKind.api);
      expect(
        result.isConnectivityFailure,
        isFalse,
        reason: 'a server rejection must never fall back to cached data',
      );
    });

    test('reads the code out of an error body that arrived as raw bytes', () {
      // A request made with `ResponseType.bytes` (the data export, and anything
      // else that downloads a file) gets bytes back even when the server said
      // no, because Dio decodes according to the request's options rather than
      // the response's type. Without the decode, every refusal on those routes
      // reads as the generic "something went wrong".
      final e = DioException(
        requestOptions: req,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: req,
          statusCode: 429,
          data: utf8.encode(
            '{"detail":{"error":"rate_limited","retry_after":86400}}',
          ),
        ),
      );
      final result = asRelayException(e);
      expect(result.error, 'rate_limited');
      expect(result.detail['retry_after'], 86400);
    });

    test('leaves a body that is not JSON alone', () {
      // A proxy's HTML error page, say. Building an exception must not throw.
      final e = DioException(
        requestOptions: req,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: req,
          statusCode: 502,
          data: utf8.encode('<html>Bad Gateway</html>'),
        ),
      );
      expect(asRelayException(e).error, 'internal_error');
    });

    test('maps 401 to unauthorized', () {
      final e = DioException(
        requestOptions: req,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: req,
          statusCode: 401,
          data: {
            'detail': {'error': 'unauthorized'},
          },
        ),
      );
      expect(asRelayException(e).kind, ApiErrorKind.unauthorized);
    });
  });

  group('messageFor', () {
    test('gives offline copy for a wrapped connection failure', () {
      final wrapped = DioException(
        requestOptions: req,
        error: RelayApiException(
          0,
          'offline',
          const {},
          kind: ApiErrorKind.offline,
        ),
      );
      expect(messageFor(en, wrapped), contains("You're offline"));
      expect(titleFor(en, wrapped), "You're offline");
    });

    test('renders the price and balance carried on insufficient_tokens', () {
      final e = RelayApiException(402, 'insufficient_tokens', const {
        'price': 5,
        'balance': 2,
      });
      final msg = messageFor(en, e);
      expect(msg, contains('need 5'));
      expect(msg, contains('you have 2'));
    });

    test('a taken username gets copy about the username, in both locales', () {
      // The backend answers this on registration and on the onboarding username
      // step (it used to be an unhandled unique-constraint violation, i.e. a
      // 500). Falling through to the generic message would tell someone whose
      // only problem is a name clash that something went wrong on our side.
      final taken = RelayApiException(409, 'username_taken', const {});

      expect(messageFor(en, taken), contains('username'));
      final unmapped = RelayApiException(400, 'something_new', const {});
      expect(messageFor(en, taken), isNot(messageFor(en, unmapped)));
      expect(messageFor(de, taken), contains('Benutzername'));
    });

    test('maps the profile-picture rejections to their own copy', () {
      // Both are real answers from the backend's upload validation, so neither
      // may fall through to the generic "something went wrong".
      final badType = RelayApiException(
        400,
        'profile_picture_invalid_type',
        const {},
      );
      final tooLarge = RelayApiException(
        400,
        'profile_picture_too_large',
        const {},
      );

      expect(messageFor(en, badType), isNot(messageFor(en, tooLarge)));
      expect(messageFor(en, badType), contains('PNG'));
      expect(messageFor(en, tooLarge), contains('2 MB'));
      // Translated, not just present in English.
      expect(messageFor(de, tooLarge), isNot(messageFor(en, tooLarge)));
      expect(messageFor(de, tooLarge), contains('2 MB'));
    });

    test('points a stale review at the fix rather than just failing', () {
      expect(
        messageFor(en, RelayApiException(409, 'not_in_queue', const {})),
        contains('refresh'),
      );
    });

    test('tells a throttled user how long to wait', () {
      final msg = messageFor(
        en,
        RelayApiException(429, 'rate_limited', const {'retry_after': 7}),
      );
      expect(msg, contains('7 seconds'));
    });

    test('singularizes a one-second wait', () {
      expect(
        messageFor(
          en,
          RelayApiException(429, 'rate_limited', const {'retry_after': 1}),
        ),
        contains('1 second.'),
      );
    });

    test('stays readable when rate_limited carries no retry_after', () {
      final msg = messageFor(
        en,
        RelayApiException(429, 'rate_limited', const {}),
      );
      expect(msg, contains('going a bit fast'));
      expect(msg, isNot(contains('null')));
    });

    test('falls back to generic copy for an unrecognized code', () {
      expect(
        messageFor(en, RelayApiException(400, 'some_new_code', const {})),
        'Something went wrong. Please try again.',
      );
    });

    test('formats the structured password-violation list from the backend', () {
      final e = RelayApiException(400, 'register_invalid_password', {
        'reason': [
          {
            'code': 'password_too_short',
            'params': {'min_length': 10},
          },
        ],
      });
      expect(messageFor(en, e), contains('at least 10 characters long'));
    });

    test('renders in German when given the German localizations', () {
      final wrapped = DioException(
        requestOptions: req,
        error: RelayApiException(
          0,
          'offline',
          const {},
          kind: ApiErrorKind.offline,
        ),
      );
      expect(messageFor(de, wrapped), contains('Du bist offline'));
      expect(titleFor(de, wrapped), 'Du bist offline');
    });

    test(
      'renders the German password-violation sentence from the same code',
      () {
        final e = RelayApiException(400, 'register_invalid_password', {
          'reason': [
            {
              'code': 'password_too_short',
              'params': {'min_length': 10},
            },
          ],
        });
        expect(messageFor(de, e), contains('mindestens 10 Zeichen lang'));
      },
    );
  });

  group('google sign-in', () {
    test(
      'a Google account gets told to use the button, not "bad password"',
      () {
        // The whole point of the dedicated code: the account's password was
        // destroyed by the upgrade, so "wrong credentials" would send the user
        // round in circles.
        final e = RelayApiException(400, 'login_use_google', const {});
        expect(messageFor(en, e), contains('signs in with Google'));
        expect(messageFor(de, e), contains('mit Google an'));
      },
    );

    test('every google_* code the backend can emit has copy', () {
      // A missing case falls through to `errorUnknown`, which is a silent
      // failure — this catches one before it ships.
      const codes = [
        'login_use_google',
        'google_account_no_password',
        'google_account_email_locked',
        'google_email_unverified',
        'google_account_in_use',
        'google_account_mismatch',
        'google_already_linked',
        'google_invalid_id_token',
        'google_verification_unavailable',
        'google_oauth_disabled',
      ];
      for (final code in codes) {
        final e = RelayApiException(400, code, const {});
        expect(
          messageFor(en, e),
          isNot(en.errorUnknown),
          reason: 'no English copy for "$code"',
        );
        expect(
          messageFor(de, e),
          isNot(de.errorUnknown),
          reason: 'no German copy for "$code"',
        );
      }
    });

    test('google_link_required deliberately has no copy', () {
      // It is a prompt, not a failure: GoogleAuthSection turns it into a
      // confirmation dialog, and it must never reach a snackbar. If someone
      // adds a case for it, that intent has been lost.
      final e = RelayApiException(409, 'google_link_required', const {
        'email': 'a@b.com',
      });
      expect(messageFor(en, e), en.errorUnknown);
    });
  });
}
