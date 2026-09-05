import 'dart:typed_data';

import 'package:dio/dio.dart';

/// What a submission is about. The wire values are the backend's
/// `FEEDBACK_KINDS` (`app/models/feedback.py`) and must stay in sync with it —
/// an unknown one is a 400 `feedback_invalid_kind`.
enum FeedbackKind {
  feedback('feedback'),
  bug('bug'),
  featureRequest('feature_request'),
  other('other');

  const FeedbackKind(this.wireValue);

  final String wireValue;

  /// Only [FeedbackKind.feedback] carries a star rating — the backend *rejects*
  /// a rating sent with any other kind rather than dropping it, so the form has
  /// to hide the stars rather than merely ignore them.
  bool get supportsRating => this == FeedbackKind.feedback;
}

/// One screenshot or screen recording picked for a submission.
///
/// Unlike `PickedMedia` in the feed repository there is no orientation and no
/// crop: the backend deliberately does not apply the two fixed post aspect
/// ratios to feedback media, because a screenshot is whatever shape the screen
/// was and a cropped screen recording loses the bug.
class FeedbackAttachment {
  FeedbackAttachment({
    required this.bytes,
    required this.filename,
    required this.contentType,
    required this.isVideo,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
  final bool isVideo;
}

class FeedbackRepository {
  FeedbackRepository(this._dio);

  final Dio _dio;

  /// `POST /feedback` — multipart, one request, whether or not there are files.
  ///
  /// Works **signed out**: the Dio interceptor simply attaches no bearer token
  /// when there is none, and the backend treats an unauthenticated submission as
  /// anonymous. That is the whole reason the form is reachable from the login
  /// screen — "I can't sign in" cannot be reported from inside the app.
  ///
  /// [consent] is sent as the user's agreement to their input being stored; the
  /// backend refuses the submission without it and stamps the *time* of that
  /// agreement from its own clock (`user_agreed_data_saving_at`), so nothing here
  /// sends a timestamp.
  Future<void> submit({
    required FeedbackKind kind,
    required String message,
    required bool consent,
    required bool isAnonymous,
    required bool allowContact,
    int? rating,
    List<FeedbackAttachment> attachments = const [],
  }) async {
    final form = FormData.fromMap({
      'kind': kind.wireValue,
      'message': message,
      'consent': consent.toString(),
      'is_anonymous': isAnonymous.toString(),
      'allow_contact': allowContact.toString(),
      if (rating != null && kind.supportsRating) 'rating': rating.toString(),
    });
    // `form.files.add(...)`, not another map entry: repeated keys in a map
    // collapse, and the backend expects every file under the same repeated
    // "files" field.
    for (final item in attachments) {
      form.files.add(
        MapEntry(
          'files',
          MultipartFile.fromBytes(
            item.bytes,
            filename: item.filename,
            contentType: DioMediaType.parse(item.contentType),
          ),
        ),
      );
    }
    await _dio.post<Map<String, dynamic>>('/feedback', data: form);
  }
}
