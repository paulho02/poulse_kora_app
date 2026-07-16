import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';

/// Wraps a [Dio] instance pointed at the backend API, attaching the stored
/// JWT bearer token (if any) to every request.
class DioClient {
  DioClient(this._tokenStorage)
      : dio = Dio(
          BaseOptions(
            baseUrl: '${AppConfig.apiBaseUrl}${AppConfig.apiPath}',
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
          handler.next(options);
        },
      ),
    );
  }

  final Dio dio;
  final TokenStorage _tokenStorage;
}
