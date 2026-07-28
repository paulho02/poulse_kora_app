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
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/users/me',
      data: {
        'bio': ?bio,
        'dark_mode': ?darkMode,
        'onboarding_completed': ?onboardingCompleted,
      },
    );
    // Keep the cache in step so a subsequent offline read doesn't resurrect the
    // pre-edit profile.
    await _cache.write(CacheKeys.profile, response.data);
    return UserProfile.fromJson(response.data!);
  }
}
