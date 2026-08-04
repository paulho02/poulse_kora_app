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
