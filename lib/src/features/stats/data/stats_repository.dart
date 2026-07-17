import 'package:dio/dio.dart';

import 'user_stats.dart';

class StatsRepository {
  StatsRepository(this._dio);

  final Dio _dio;

  Future<UserStats> fetchStats() async {
    final response = await _dio.get<Map<String, dynamic>>('/stats/me');
    return UserStats.fromJson(response.data!);
  }
}
