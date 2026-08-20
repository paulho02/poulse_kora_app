import 'package:dio/dio.dart';

/// Talks to the backend's fastapi-users auth endpoints.
class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  /// `POST /auth/jwt/login` expects `application/x-www-form-urlencoded` with
  /// `username`/`password` fields (fastapi-users' stock
  /// `OAuth2PasswordRequestForm` contract) — not JSON.
  Future<String> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/jwt/login',
      data: FormData.fromMap({'username': email, 'password': password}),
    );
    return response.data!['access_token'] as String;
  }

  Future<void> register({
    required String email,
    required String password,
    required String username,
  }) async {
    await _dio.post<void>(
      '/auth/register',
      data: {'email': email, 'password': password, 'username': username},
    );
  }

  /// `POST /auth/google` — exchanges a Google ID token for our own access token,
  /// creating the account if the address is new.
  ///
  /// Throws `google_link_required` (409) when the address already belongs to a
  /// password account: the caller must confirm with the user that the upgrade is
  /// permanent, then call this again with the *same* [idToken] and
  /// [linkExisting] true. Google ID tokens live about an hour, so re-sending one
  /// after a dialog is fine.
  Future<String> loginWithGoogle({
    required String idToken,
    bool linkExisting = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/google',
      data: {'id_token': idToken, 'link_existing': linkExisting},
    );
    return response.data!['access_token'] as String;
  }

  /// `POST /auth/google/link` — the same irreversible upgrade, for a user who is
  /// already signed in (Profile → Settings). The Google address must match the
  /// account's own.
  Future<void> linkGoogle({required String idToken}) async {
    await _dio.post<void>('/auth/google/link', data: {'id_token': idToken});
  }

  /// Requires the current password server-side — see
  /// `backend/app/api/change_password.py`. `PATCH /users/me` deliberately
  /// cannot change the password at all, so this is the only path.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _dio.post<void>(
      '/auth/change-password',
      data: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }
}
