import 'package:dio/dio.dart';

import 'public_app_config.dart';

class AppConfigRepository {
  AppConfigRepository(this._dio);
  final Dio _dio;

  /// GET /config — public, no auth, callable pre-login.
  Future<PublicAppConfig> fetchConfig() async {
    final response = await _dio.get<Map<String, dynamic>>('/config');
    return PublicAppConfig.fromJson(response.data!);
  }
}
