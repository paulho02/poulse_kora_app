import '../errors/api_exception.dart';
import 'cached.dart';
import 'json_cache.dart';

/// Fetch from the network, write through to the cache, and fall back to the last
/// good copy when — and only when — the network was unreachable.
///
/// The "only when" is the important part. A 401, 403 or 404 is a real answer from
/// the server, and quietly serving stale data over it would hide an expired
/// session behind a feed that looks like it's working. Those propagate.
Future<Cached<T>> fetchCached<T>({
  required JsonCache cache,
  required String key,
  required Future<dynamic> Function() fetchJson,
  required T Function(dynamic json) parse,
}) async {
  try {
    final json = await fetchJson();
    // Store the raw JSON rather than the parsed object: it round-trips without
    // needing a toJson() on every model, and stays readable if the model changes.
    await cache.write(key, json);
    return Cached.live(parse(json));
  } catch (e) {
    final failure = asPeerkolaException(e);
    if (!failure.isConnectivityFailure) rethrow;
    final cached = cache.read<T>(key, parse);
    if (cached == null) rethrow;
    return cached;
  }
}
