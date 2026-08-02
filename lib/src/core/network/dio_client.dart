import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../errors/api_exception.dart';
import '../storage/token_storage.dart';
import 'connectivity.dart';

/// Wraps a [Dio] instance pointed at the backend API.
///
/// Three interceptors, in order:
///  1. attach the stored JWT bearer token,
///  2. report every outcome to [ConnectivityNotifier] so the offline banner
///     reflects reality rather than just link state,
///  3. convert every [DioException] into a [RelayApiException], so no repository
///     or screen ever sees a raw Dio type. This is centralized here because the
///     alternative — per-method try/catch — drifted: error shape used to depend
///     on which call you happened to make.
class DioClient {
  DioClient(
    this._tokenStorage, {
    required String baseUrl,
    required ConnectivityNotifier connectivity,
    required Future<void> Function() onUnauthorized,
    required String Function() localeCode,
  }) : dio = Dio(
         BaseOptions(
           baseUrl: '$baseUrl${AppConfig.apiPath}',
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 10),
         ),
       ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStorage.readAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          // Lets the backend localize what little user-facing prose it
          // generates itself (banner text, password-policy messages) — see
          // `backend/app/deps/locale.py`. Kept in sync with `MaterialApp`'s
          // `locale` via the same `activeLocaleProvider`.
          options.headers['Accept-Language'] = localeCode();
          handler.next(options);
        },
        onResponse: (response, handler) {
          connectivity.reportSuccess();
          handler.next(response);
        },
        onError: (e, handler) async {
          final failure = RelayApiException.fromDioException(e);

          if (failure.isConnectivityFailure) {
            connectivity.reportFailure();
          } else {
            // We got *an* answer, so the server is reachable even if it said no.
            connectivity.reportSuccess();
          }

          // No refresh-token flow exists (fastapi-users issues a single JWT), so
          // an expired token can only be resolved by signing in again. Without
          // this, expiry surfaces as a confusing error on every screen at once.
          if (failure.kind == ApiErrorKind.unauthorized) {
            await onUnauthorized();
          }

          handler.reject(
            DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: e.type,
              error: failure,
            ),
          );
        },
      ),
    );
  }

  final Dio dio;
  final TokenStorage _tokenStorage;
}
