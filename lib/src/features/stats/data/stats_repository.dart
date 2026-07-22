import 'package:dio/dio.dart';

import 'global_stats.dart';
import 'user_stats.dart';

class StatsRepository {
  StatsRepository(this._dio);

  final Dio _dio;

  Future<UserStats> fetchStats() async {
    final response = await _dio.get<Map<String, dynamic>>('/stats/me');
    return UserStats.fromJson(response.data!);
  }

  Future<GlobalStats> fetchGlobalStats() async {
    final response = await _dio.get<Map<String, dynamic>>('/stats/global');
    return GlobalStats.fromJson(response.data!);
  }
}
