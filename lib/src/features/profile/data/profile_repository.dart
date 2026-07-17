import 'package:dio/dio.dart';

import 'user_profile.dart';

class ProfileRepository {
  ProfileRepository(this._dio);

  final Dio _dio;

  Future<UserProfile> fetchMe() async {
    final response = await _dio.get<Map<String, dynamic>>('/users/me');
    return UserProfile.fromJson(response.data!);
  }

  Future<UserProfile> updateMe({String? bio, bool? darkMode}) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/users/me',
      data: {
        'bio': ?bio,
        'dark_mode': ?darkMode,
      },
    );
    return UserProfile.fromJson(response.data!);
  }
}
