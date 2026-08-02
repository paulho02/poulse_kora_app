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
}
