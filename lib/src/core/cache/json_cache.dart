import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cached.dart';

/// Last-known-good API responses, stored as JSON blobs in `SharedPreferences`.
///
/// Deliberately not a database: the cached set is a ~20-post review queue, a
/// channel list, a profile and some counters. A relational store would buy
/// nothing at this size and costs a schema to migrate. It also works unchanged
/// on the Web target.
///
/// Isolation between accounts is by wiping the cache at both ends of a session
/// ([clearAll] on login and on logout) rather than by namespacing keys per user.
/// Namespacing looked tidier but was wrong in practice: the user id only becomes
/// known once `/users/me` returns, so everything cached before that — the feed
/// included — was written under one scope and then looked up under another, and
/// silently never read back. Wiping has no such ordering hazard, and it still
/// holds if a session ends without a clean logout.
class JsonCache {
  JsonCache(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = 'cache';

  String _fullKey(String key) => '$_prefix:$key';

  Future<void> write(String key, Object? payload) async {
    await _prefs.setString(
      _fullKey(key),
      jsonEncode({
        'fetchedAt': DateTime.now().toIso8601String(),
        'payload': payload,
      }),
    );
  }

  /// Returns the stored value, or `null` if absent or unreadable.
  ///
  /// A decode failure is treated as a miss rather than an error: the cache is an
  /// optimization, and a stale entry written by an older app version must never
  /// be able to crash a screen.
  Cached<T>? read<T>(String key, T Function(dynamic json) parse) {
    final raw = _prefs.getString(_fullKey(key));
    if (raw == null) return null;
    try {
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      final fetchedAt = DateTime.parse(envelope['fetchedAt'] as String);
      return Cached.stale(parse(envelope['payload']), fetchedAt);
    } catch (_) {
      _prefs.remove(_fullKey(key));
      return null;
    }
  }

  /// Drops every cached entry. Called at both ends of a session.
  Future<void> clearAll() async {
    final keys = _prefs
        .getKeys()
        .where((k) => k.startsWith('$_prefix:'))
        .toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}

/// Cache keys. Centralized so a key can't silently diverge between the write in
/// a repository and a read somewhere else.
class CacheKeys {
  CacheKeys._();

  /// The feed is filtered per channel and each filter has its own queue view,
  /// so the selected channel has to be part of the key.
  static String feed(int? channelId) => 'feed:${channelId ?? 'all'}';
  static const channels = 'channels';
  static const profile = 'profile';
  static const userStats = 'stats:user';
  static const ownPostViews = 'stats:posts';
  static const trendingPosts = 'stats:trending';
  static const trendingChannels = 'stats:trending:channels';
  static const economy = 'economy';
}
