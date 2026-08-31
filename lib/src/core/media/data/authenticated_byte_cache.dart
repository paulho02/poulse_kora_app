import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';
import '../../errors/api_exception.dart';

/// In-memory store of bytes fetched from an auth-required backend route, keyed by
/// the URL the backend hands out (e.g. `UserRead.profile_picture_url`,
/// `PostMediaRead.url`).
///
/// This exists because such bytes are **not** plain `Image.network` material: the
/// routes serving them require the bearer token, and only the [Dio] instance from
/// `core/network/dio_client.dart` attaches it. So the bytes are fetched like any
/// other API call and rendered with `Image.memory`.
///
/// One instance is shared per *kind* of image (see the `*CacheProvider`s in
/// `core/media/application/media_providers.dart` and
/// `core/avatars/application/avatar_providers.dart`) rather than per widget:
/// a feed screen holds many cards, often repeating the same author or the same
/// post image, and cards are rebuilt constantly while scrolling — without this,
/// every rebuild would re-request the same bytes. Entries are held for the
/// lifetime of the session and dropped by [clear] at a session boundary.
///
/// A [ChangeNotifier], because dropping an entry has to reach widgets that are
/// *already on screen*. A URL can be derived from an id and so stay unchanged
/// when the bytes behind it change (e.g. a replaced profile picture) - a widget
/// diffing its own inputs would never notice, and would keep painting the bytes
/// it fetched first.
class AuthenticatedByteCache extends ChangeNotifier {
  AuthenticatedByteCache(this._dio);

  final Dio _dio;

  /// A present key means "already resolved"; a null *value* means "resolved to
  /// nothing" (fetch failed). Storing the negative result matters as much as the
  /// positive one: without it, a failed fetch would be retried on every rebuild.
  final Map<String, Uint8List?> _bytes = {};

  /// Requests in flight, so N widgets requesting the same URL share one round
  /// trip instead of racing N identical ones.
  final Map<String, Future<Uint8List?>> _inFlight = {};

  /// Synchronous peek, for rendering without a frame of placeholder when the
  /// bytes are already here. [isResolved] distinguishes "not fetched yet" from
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
      // Deliberately cached as a miss, including for a connectivity failure: this
      // is decoration, and retrying per rebuild while offline would mean a
      // request storm behind a screen that already shows the fallback perfectly
      // well. `clear()`/`refresh()` on reconnect is what lets it load again.
      //
      // Unwrapped only to keep the analyzer honest about the catch being
      // intentional; nothing here needs the code, since there is no message to
      // show for decoration that quietly stays a fallback.
      asRelayException(e);
      _bytes[url] = null;
      return null;
    } finally {
      _inFlight.remove(url);
    }
  }

  /// Forget one entry and have anything showing it load again.
  ///
  /// Used after the current user replaces or removes bytes at this URL. The URL
  /// is identical before and after, so this notification is the only thing that
  /// tells an on-screen widget its pixels are stale.
  void evict(String url) {
    _bytes.remove(url);
    _inFlight.remove(url);
    notifyListeners();
  }

  /// Drop everything and reload what is on screen.
  ///
  /// For coming back online: failures are cached as misses, so without this
  /// anything that failed while offline would stay a fallback for the rest of
  /// the session — the entries are only consulted once per widget.
  void refresh() {
    _bytes.clear();
    _inFlight.clear();
    notifyListeners();
  }

  /// Drop everything *without* asking anyone to reload.
  ///
  /// For a session boundary. Deliberately silent, unlike [refresh]: the token
  /// these entries were fetched with is being thrown away, so waking mounted
  /// widgets here would only fire a burst of requests that are about to 401 —
  /// and the screens holding them are being torn down regardless.
  void clear() {
    _bytes.clear();
    _inFlight.clear();
  }

  /// The backend returns an absolute API path (e.g.
  /// `/api/v1/users/…/profile-picture`) because that is what a URL means to any
  /// other client. Dio's `baseUrl` already ends in the same prefix, so passing it
  /// through unchanged would request `/api/v1/api/v1/…`.
  static String _toApiRelativePath(String url) =>
      url.startsWith(AppConfig.apiPath)
      ? url.substring(AppConfig.apiPath.length)
      : url;
}
