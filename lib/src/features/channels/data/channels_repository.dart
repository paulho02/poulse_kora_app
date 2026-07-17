import 'package:dio/dio.dart';

import 'channel.dart';

class ChannelsRepository {
  ChannelsRepository(this._dio);

  final Dio _dio;

  Future<List<Channel>> fetchChannels({String? query}) async {
    final response = await _dio.get<List<dynamic>>(
      '/channels',
      queryParameters: {if (query != null && query.isNotEmpty) 'q': query},
    );
    return response.data!
        .map((json) => Channel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Channel> subscribe(int channelId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/channels/$channelId/subscribe',
    );
    return Channel.fromJson(response.data!);
  }

  Future<Channel> unsubscribe(int channelId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/channels/$channelId/unsubscribe',
    );
    return Channel.fromJson(response.data!);
  }
}
