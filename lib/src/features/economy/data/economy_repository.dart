import 'package:dio/dio.dart';

import 'economy.dart';

class EconomyRepository {
  EconomyRepository(this._dio);

  final Dio _dio;

  /// GET /posts/economy — current token balance and live post price.
  Future<Economy> fetchEconomy() async {
    final response = await _dio.get<Map<String, dynamic>>('/posts/economy');
    return Economy.fromJson(response.data!);
  }
}
