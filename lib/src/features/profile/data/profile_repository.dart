import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/cache/cached.dart';
import '../../../core/cache/cached_fetch.dart';
import '../../../core/cache/json_cache.dart';
import 'data_export.dart';
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
  /// Set which languages this reader accepts posts in.
  ///
  /// Its own endpoint rather than a field on the profile PATCH, because the
  /// column is only half the change server-side: the other half is rewriting
  /// the Redis audience memberships fan-out actually samples. Sends the whole
  /// set, not a delta — the backend writes it absolutely, which is what makes
  /// re-sending the same value a no-op rather than a conflict for the user's
  /// other devices.
  Future<UserProfile> setContentLanguages(List<String> languages) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/users/me/content-languages',
      data: {'languages': languages},
    );
    return UserProfile.fromJson(response.data!);
  }

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

  /// Download everything the backend holds about this account, as a ZIP.
  ///
  /// The GDPR Art. 15 / Art. 20 copy (`GET /users/me/export`): a README, a
  /// `data.json` and every file the account ever uploaded. Three things here are
  /// not the defaults:
  ///
  /// - **The whole body is held in memory.** Dio's `download()` streams to a
  ///   file, but only on platforms with a filesystem, and this app runs on the
  ///   web too - so an export that is enormous is a problem on a phone. It is
  ///   the right trade today: the archive is one person's posts and pictures,
  ///   and the alternative is two code paths for a once-a-year action.
  /// - **A long receive timeout.** The client-wide 10 seconds is sized for JSON;
  ///   this response is built as it is sent, so the server may legitimately be
  ///   quiet while it reads a video out of the bucket. Dio applies the timeout
  ///   between chunks rather than to the whole transfer, so this is a stall
  ///   detector, not a size limit.
  /// - **Nothing is cached.** `JsonCache` is for things the app re-reads while
  ///   offline; a copy of an account's personal data has no business sitting in
  ///   `shared_preferences` afterwards.
  Future<DataExport> downloadDataExport({
    void Function(int received, int total)? onProgress,
  }) async {
    final response = await _dio.get<List<int>>(
      '/users/me/export',
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 10),
      ),
      onReceiveProgress: onProgress,
    );
    return DataExport(
      filename: DataExport.filenameFrom(
        response.headers.value('content-disposition'),
      ),
      bytes: Uint8List.fromList(response.data!),
    );
  }

  /// Erase the account, and its posts too when [deletePosts] is set.
  ///
  /// Irreversible, and the caller is expected to have confirmed twice (see
  /// `DeleteAccountDialog`). [currentPassword] is required by the backend for a
  /// password account and meaningless for a Google one, whose stored hash is a
  /// random value nobody holds.
  ///
  /// Writes nothing to the cache on the way out: the whole cache is wiped by the
  /// sign-out that follows, and a profile written here would be a copy of an
  /// account that no longer exists.
  Future<void> deleteAccount({
    required bool deletePosts,
    String? currentPassword,
  }) async {
    await _dio.delete<void>(
      '/users/me',
      data: {'delete_posts': deletePosts, 'current_password': ?currentPassword},
    );
  }

  Future<UserProfile> deleteProfilePicture() async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/users/me/profile-picture',
    );
    await _cache.write(CacheKeys.profile, response.data);
    return UserProfile.fromJson(response.data!);
  }
}
