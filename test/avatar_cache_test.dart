import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/src/core/avatars/application/avatar_providers.dart';
import 'package:poulse_kora_app/src/core/avatars/data/avatar_cache.dart';
import 'package:poulse_kora_app/src/core/avatars/presentation/user_avatar.dart';

/// Serves whatever bytes the test currently wants, and counts requests.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.bytes);

  List<int> bytes;
  var calls = 0;
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    paths.add(options.path);
    return ResponseBody.fromBytes(bytes, 200);
  }

  @override
  void close({bool force = false}) {}
}

const _url = '/api/v1/users/abc/profile-picture';

AvatarCache _cacheWith(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
  dio.httpClientAdapter = adapter;
  return AvatarCache(dio);
}

void main() {
  group('AvatarCache', () {
    test('strips the API prefix the backend puts on the URL', () async {
      final adapter = _FakeAdapter([1, 2, 3]);
      await _cacheWith(adapter).load(_url);
      // Dio's baseUrl already ends in /api/v1; sending the URL through unchanged
      // would request /api/v1/api/v1/...
      expect(adapter.paths.single, '/users/abc/profile-picture');
    });

    test('fetches once, then serves from memory', () async {
      final adapter = _FakeAdapter([1, 2, 3]);
      final cache = _cacheWith(adapter);

      expect(await cache.load(_url), [1, 2, 3]);
      expect(await cache.load(_url), [1, 2, 3]);
      expect(adapter.calls, 1);
    });

    test('shares one request between concurrent callers', () async {
      // A feed with several posts by the same author asks all at once.
      final adapter = _FakeAdapter([1, 2, 3]);
      final cache = _cacheWith(adapter);

      await Future.wait([cache.load(_url), cache.load(_url), cache.load(_url)]);
      expect(adapter.calls, 1);
    });

    test('evict forces the next load to go back to the network', () async {
      final adapter = _FakeAdapter([1, 2, 3]);
      final cache = _cacheWith(adapter);
      await cache.load(_url);

      adapter.bytes = [9, 9, 9];
      cache.evict(_url);

      expect(await cache.load(_url), [9, 9, 9]);
      expect(adapter.calls, 2);
    });

    test('evict and refresh notify listeners; clear deliberately does not',
        () async {
      final cache = _cacheWith(_FakeAdapter([1]));
      var notifications = 0;
      cache.addListener(() => notifications++);

      cache.evict(_url);
      expect(notifications, 1);

      cache.refresh();
      expect(notifications, 2);

      // Silent on purpose: a session boundary is throwing the token away, so
      // waking on-screen avatars would only fire requests destined to 401.
      cache.clear();
      expect(notifications, 2);
    });
  });

  group('UserAvatar', () {
    testWidgets('picks up a replaced picture at an unchanged URL', (
      tester,
    ) async {
      // The regression this guards: the URL is derived from the user id, so it
      // is byte-for-byte identical before and after a replacement. Nothing the
      // widget can diff about its own inputs changes, so before the cache became
      // observable the old picture stayed on screen until an app restart.
      final adapter = _FakeAdapter(_pngBytes(const Color(0xFFFF0000)));
      final cache = _cacheWith(adapter);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [avatarCacheProvider.overrideWithValue(cache)],
          child: const MaterialApp(
            home: UserAvatar(
              imageUrl: _url,
              radius: 20,
              fallback: MonogramAvatar(seed: 'ada', radius: 20),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(adapter.calls, 1);

      // Replace the picture, exactly as ProfileNotifier does after an upload.
      adapter.bytes = _pngBytes(const Color(0xFF00FF00));
      cache.evict(_url);
      await tester.pumpAndSettle();

      expect(
        adapter.calls,
        2,
        reason: 'the avatar must re-fetch when its entry is evicted',
      );
    });

    testWidgets('a cleared cache does not wake mounted avatars', (
      tester,
    ) async {
      final adapter = _FakeAdapter(_pngBytes(const Color(0xFFFF0000)));
      final cache = _cacheWith(adapter);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [avatarCacheProvider.overrideWithValue(cache)],
          child: const MaterialApp(
            home: UserAvatar(
              imageUrl: _url,
              radius: 20,
              fallback: MonogramAvatar(seed: 'ada', radius: 20),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      cache.clear();
      await tester.pumpAndSettle();

      expect(adapter.calls, 1, reason: 'logout must not trigger a refetch');
    });
  });
}

/// A 1x1 PNG. Content does not matter — only that `Image.memory` can decode it,
/// since a decode failure would surface as an unrelated widget error.
Uint8List _pngBytes(Color color) {
  // Minimal valid 1x1 PNG (the colour argument only keeps call sites readable).
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
    0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
    0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
}
