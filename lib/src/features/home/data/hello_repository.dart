import 'package:dio/dio.dart';

class HelloRepository {
  HelloRepository(this._dio);

  final Dio _dio;

  Future<String> fetchHelloMessage() async {
    final response = await _dio.get<Map<String, dynamic>>('/hello-world');
    return response.data!['msg'] as String;
  }
}
