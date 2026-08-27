import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';
import '../../errors/api_exception.dart';

/// In-memory store of profile-picture bytes, keyed by the URL the backend hands
/// out on `UserRead.profile_picture_url` / `PostAuthor.profile_picture_url`.
///
/// This exists because the pictures are **not** plain `Image.network` material:
/// `GET /users/{id}/profile-picture` requires the bearer token, and only the
/// [Dio] instance from `core/network/dio_client.dart` attaches it. So the bytes
/// are fetched like any other API call and rendered with `Image.memory`.
///
/// Memoizing is what makes that affordable. A feed screen holds many cards, often
/// several by the same author, and cards are rebuilt constantly while scrolling —
/// without this, every rebuild would re-request the same image. Entries are held
/// for the lifetime of the session and dropped by [clear] at a session boundary
/// (see `_invalidateSessionScoped` in `app.dart`), so one account's pictures can
/// never be shown to the next.
///
/// A [ChangeNotifier], because dropping an entry has to reach avatars that are
/// *already on screen*. Their URL is derived from the user id and so does not
/// change when the picture behind it does — a widget diffing its own inputs can
/// therefore never notice, and would keep painting the bytes it fetched first.
class AvatarCache extends ChangeNotifier {
  AvatarCache(this._dio);

  final Dio _dio;

  /// A present key means "already resolved"; a null *value* means "resolved to
  /// nothing" (no picture, or a failure). Storing the negative result matters as
  /// much as the positive one: without it, an author with no picture would be
  /// re-requested on every single rebuild.
  final Map<String, Uint8List?> _bytes = {};

  /// Requests in flight, so N cards by the same author share one round trip
  /// instead of racing N identical ones.
  final Map<String, Future<Uint8List?>> _inFlight = {};

  /// Synchronous peek, for rendering without a frame of placeholder when the
  /// image is already here. [isResolved] distinguishes "not fetched yet" from
  /// "fetched, and there is nothing to show" — both of which read as null.
  Uint8List? peek(String url) => _bytes[url];

  bool isResolved(String url) => _bytes.containsKey(url);

  Future<Uint8List?> load(String url) {
    if (_bytes.containsKey(url)) return Future.value(_bytes[url]);
    final existing = _inFlight[url];
    if (existing != null) return existing;

    final future = _fetch(url);
    _inFlight[url] = future;
    return future;
  }

  Future<Uint8List?> _fetch(String url) async {
    try {
      final response = await _dio.get<List<int>>(
        _toApiRelativePath(url),
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      final bytes = data == null ? null : Uint8List.fromList(data);
      _bytes[url] = bytes;
      return bytes;
    } catch (e) {
      // Deliberately cached as a miss, including for a connectivity failure:
      // an avatar is decoration, and retrying per rebuild while offline would
      // mean a request storm behind a screen that already shows the fallback
      // initial perfectly well. `clear()` on reconnect is what lets them load
      // again — see the ConnectionStatus listener in `app.dart`.
      //
      // Unwrapped only to keep the analyzer honest about the catch being
      // intentional; nothing here needs the code, since there is no message to
      // show for an avatar that quietly stays a monogram.
      asRelayException(e);
      _bytes[url] = null;
      return null;
    } finally {
      _inFlight.remove(url);
    }
  }

  /// Forget one entry and have anything showing it load again.
  ///
  /// Used after the current user replaces or removes their own picture. The URL
  /// is identical before and after, so this notification is the only thing that
  /// tells an on-screen avatar its pixels are stale.
  void evict(String url) {
    _bytes.remove(url);
    _inFlight.remove(url);
    notifyListeners();
  }

  /// Drop everything and reload what is on screen.
  ///
  /// For coming back online: failures are cached as misses, so without this the
  /// avatars that failed while offline would stay monograms for the rest of the
  /// session — the entries are only consulted once per widget.
  void refresh() {
    _bytes.clear();
    _inFlight.clear();
    notifyListeners();
  }

  /// Drop everything *without* asking anyone to reload.
  ///
  /// For a session boundary. Deliberately silent, unlike [refresh]: the token
  /// these entries were fetched with is being thrown away, so waking mounted
  /// avatars here would only fire a burst of requests that are about to 401 —
  /// and the screens holding them are being torn down regardless.
  void clear() {
    _bytes.clear();
    _inFlight.clear();
  }

  /// The backend returns an absolute API path (`/api/v1/users/…/profile-picture`)
  /// because that is what a URL means to any other client. Dio's `baseUrl`
  /// already ends in the same prefix, so passing it through unchanged would
  /// request `/api/v1/api/v1/…`.
  static String _toApiRelativePath(String url) =>
      url.startsWith(AppConfig.apiPath)
      ? url.substring(AppConfig.apiPath.length)
      : url;
}
