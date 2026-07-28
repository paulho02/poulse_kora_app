import 'package:dio/dio.dart';

import 'announcement.dart';

class AnnouncementRepository {
  AnnouncementRepository(this._dio);
  final Dio _dio;

  /// GET /banner — public, no auth, callable pre-login. Returns null when
  /// nothing is currently set (backend responds with a JSON `null` body).
  ///
  /// Deliberately not cached: serving a *stale* announcement after a failed
  /// fetch would be actively misleading (e.g. a maintenance notice lingering
  /// after the admin already cleared it) — a failure here must mean "show
  /// nothing", not "show the last thing we saw".
  Future<Announcement?> fetchAnnouncement() async {
    final response = await _dio.get<Map<String, dynamic>?>('/banner');
    final data = response.data;
    if (data == null) return null;
    return Announcement.fromJson(data);
  }
}
