import 'package:dio/dio.dart';

import '../../../core/cache/cached.dart';
import '../../../core/cache/cached_fetch.dart';
import '../../../core/cache/json_cache.dart';
import 'user_profile.dart';

class ProfileRepository {
  ProfileRepository(this._dio, this._cache);

  final Dio _dio;
  final JsonCache _cache;

  Future<Cached<UserProfile>> fetchMe() {
    return fetchCached<UserProfile>(
      cache: _cache,
      key: CacheKeys.profile,
      fetchJson: () async {
        final response = await _dio.get<Map<String, dynamic>>('/users/me');
        return response.data!;
      },
      parse: (json) => UserProfile.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<UserProfile> updateMe({
    String? bio,
    bool? darkMode,
    bool? onboardingCompleted,
    String? username,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/users/me',
      data: {
        'bio': ?bio,
        'dark_mode': ?darkMode,
        'onboarding_completed': ?onboardingCompleted,
        'username': ?username,
      },
    );
    // Keep the cache in step so a subsequent offline read doesn't resurrect the
    // pre-edit profile.
    await _cache.write(CacheKeys.profile, response.data);
    return UserProfile.fromJson(response.data!);
  }

  /// Replace the current user's profile picture.
  ///
  /// A multipart upload rather than a field on [updateMe]: the bytes go to
  /// `PUT /users/me/profile-picture`, which is where the backend enforces the
  /// size and content-type limits (see `PROFILE_PICTURE_*` in its config).
  Future<UserProfile> uploadProfilePicture({
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/users/me/profile-picture',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          // The backend validates against this, not the extension, so it has to
          // be the real type of the bytes rather than a generic default.
          contentType: DioMediaType.parse(contentType),
        ),
      }),
    );
    await _cache.write(CacheKeys.profile, response.data);
    return UserProfile.fromJson(response.data!);
  }

  Future<UserProfile> deleteProfilePicture() async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/users/me/profile-picture',
    );
    await _cache.write(CacheKeys.profile, response.data);
    return UserProfile.fromJson(response.data!);
  }
}
