import 'package:dio/dio.dart';

/// Talks to the backend's short-code email verification endpoints (see backend
/// `app/api/email_verification.py`). Not fastapi-users' own verify flow - that
/// mails a link-style token, whereas the app wants a code typed in after
/// registration.
class EmailVerificationRepository {
  EmailVerificationRepository(this._dio);
  final Dio _dio;

  /// Returns the account's verified status. Throws `invalid_verification_code`
  /// (with `attempts_remaining`), `verification_code_expired` or
  /// `too_many_verification_attempts` on failure - see error_messages.dart.
  Future<bool> confirm(String code) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/email-verification/confirm',
      data: {'code': code},
    );
    return response.data!['is_verified'] as bool;
  }

  /// Throws `resend_cooldown` (with `retry_after` seconds) if called again too
  /// soon - see error_messages.dart.
  Future<bool> resend() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/email-verification/resend',
    );
    return response.data!['is_verified'] as bool;
  }
}
