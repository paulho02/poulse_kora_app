import 'package:dio/dio.dart';

/// Why a request failed, at the level the UI actually cares about.
///
/// The distinction that matters most is [offline] vs everything else: an offline
/// failure is expected and recoverable, so it gets a calm message and lets cached
/// content stay on screen, whereas the others mean the server said no.
enum ApiErrorKind {
  /// The request never reached the server (no route to host, connection refused,
  /// DNS failure). Also covers "wifi is up but the backend is down".
  offline,

  /// The server was reachable but took too long to answer.
  timeout,

  /// The server answered with a business-rule rejection (4xx) — see [error] for
  /// the machine-readable code.
  api,

  /// The token is missing, expired or rejected.
  unauthorized,

  /// The server blew up (5xx).
  server,

  /// Anything we couldn't classify, including request cancellation.
  unknown,
}

/// A failed API call, normalized into one shape regardless of where it failed.
///
/// Every `DioException` is converted to this by the interceptor in
/// `core/network/dio_client.dart`, so repositories and screens never handle raw
/// Dio types. Map one to display copy with `messageFor` in `error_messages.dart`
/// — don't build user-facing strings from [error] at the call site.
class RelayApiException implements Exception {
  RelayApiException(
    this.statusCode,
    this.error,
    this.detail, {
    this.kind = ApiErrorKind.api,
  });

  final int statusCode;

  /// The backend's machine-readable code (`insufficient_tokens`, `not_in_queue`,
  /// …), or a synthetic one like `offline` when the request never landed.
  final String error;

  /// The full `detail` object, carrying extra context the message may want —
  /// e.g. `balance` and `price` on `insufficient_tokens`.
  final Map<String, dynamic> detail;

  final ApiErrorKind kind;

  /// True when retrying later, unchanged, could plausibly succeed. Used to decide
  /// whether serving stale cached data instead of an error is honest.
  bool get isConnectivityFailure =>
      kind == ApiErrorKind.offline || kind == ApiErrorKind.timeout;

  @override
  String toString() => 'RelayApiException($statusCode, $error, ${kind.name})';

  factory RelayApiException.fromDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return RelayApiException(
          0,
          'offline',
          const {},
          kind: ApiErrorKind.offline,
        );
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return RelayApiException(
          0,
          'timeout',
          const {},
          kind: ApiErrorKind.timeout,
        );
      case DioExceptionType.badCertificate:
        return RelayApiException(
          0,
          'bad_certificate',
          const {},
          kind: ApiErrorKind.unknown,
        );
      case DioExceptionType.cancel:
        return RelayApiException(
          0,
          'cancelled',
          const {},
          kind: ApiErrorKind.unknown,
        );
      case DioExceptionType.unknown:
        // Dio reports socket failures as `unknown` on some platforms (notably
        // web, where the browser hides the reason for a failed fetch). Treat a
        // response-less unknown as offline: the alternative is showing a scary
        // generic error for the ordinary case of the server being unreachable.
        if (e.response == null) {
          return RelayApiException(
            0,
            'offline',
            const {},
            kind: ApiErrorKind.offline,
          );
        }
        break;
      case DioExceptionType.badResponse:
        break;
      default:
        // Newer Dio versions may add cases (e.g. transformTimeout); a
        // response-less failure is still, from the user's side, "didn't land".
        if (e.response == null) {
          return RelayApiException(
            0,
            'offline',
            const {},
            kind: ApiErrorKind.offline,
          );
        }
        break;
    }

    final status = e.response?.statusCode ?? 0;
    final detail = _extractDetail(e.response?.data);
    return RelayApiException(
      status,
      detail['error'] as String? ?? _fallbackCodeFor(status),
      detail,
      kind: _kindForStatus(status),
    );
  }

  /// The backend wraps every error as `{"detail": {"error": ..., ...}}`
  /// (see `app/core/errors.py`). Older/edge responses may still carry a string
  /// detail, so degrade rather than throwing while building an error.
  static Map<String, dynamic> _extractDetail(dynamic data) {
    if (data is Map && data['detail'] is Map) {
      return Map<String, dynamic>.from(data['detail'] as Map);
    }
    if (data is Map && data['detail'] is String) {
      return {'message': data['detail'] as String};
    }
    return const {};
  }

  static ApiErrorKind _kindForStatus(int status) {
    if (status == 401 || status == 403) return ApiErrorKind.unauthorized;
    if (status >= 500) return ApiErrorKind.server;
    if (status >= 400) return ApiErrorKind.api;
    return ApiErrorKind.unknown;
  }

  static String _fallbackCodeFor(int status) {
    if (status == 401 || status == 403) return 'unauthorized';
    if (status >= 500) return 'internal_error';
    return 'unknown';
  }
}

/// Unwraps whatever a failed call threw into a [RelayApiException].
///
/// The interceptor in `core/network/dio_client.dart` tucks the normalized
/// failure into `DioException.error`, but Dio insists on rethrowing its own type
/// — and `AsyncValue.guard` then hands that raw `DioException` to the widget. So
/// anything that inspects an error must funnel through here first, or an offline
/// failure reads as a generic "something went wrong".
RelayApiException asRelayException(Object? error) {
  if (error is RelayApiException) return error;
  if (error is DioException) {
    final inner = error.error;
    if (inner is RelayApiException) return inner;
    return RelayApiException.fromDioException(error);
  }
  return RelayApiException(0, 'unknown', const {}, kind: ApiErrorKind.unknown);
}
