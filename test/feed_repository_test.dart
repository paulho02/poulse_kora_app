import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:peerkola/src/core/cache/json_cache.dart';
import 'package:peerkola/src/features/feed/data/feed_repository.dart';

/// Captures the request `createPost` actually sends, and answers with a
/// minimal-but-valid `PostCreateResult` body.
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  FormData? lastFormData;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    lastFormData = options.data as FormData?;

    final body = jsonEncode({
      'post': {
        'id': 1,
        'channel_id': 1,
        'channel_name': 'General',
        'blocks': [
          {'type': 'text', 'text': 'hi', 'media': null},
        ],
        'is_anonymous': false,
        'author': {'id': null, 'username': null, 'profile_picture_url': null},
        'subscription_kind': null,
        'created': DateTime.now().toUtc().toIso8601String(),
      },
      'price': 3,
      'token_balance': 7,
    });
    return ResponseBody.fromString(
      body,
      201,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<FeedRepository> _repository(_CapturingAdapter adapter) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
  dio.httpClientAdapter = adapter;
  return FeedRepository(dio, JsonCache(prefs));
}

void main() {
  group('FeedRepository.createPost', () {
    test(
      'sends a multipart request with no files field when there is no media',
      () async {
        final adapter = _CapturingAdapter();
        final repo = await _repository(adapter);

        await repo.createPost(
          channelId: 2,
          blocks: [ComposerBlockInput.text('hello')],
          language: 'en',
          isAnonymous: true,
        );

        final form = adapter.lastFormData!;
        expect(adapter.lastRequest!.method, 'POST');
        final fields = {for (final e in form.fields) e.key: e.value};
        expect(fields['channel_id'], '2');
        expect(fields['is_anonymous'], 'true');
        expect(jsonDecode(fields['blocks']!), [
          {'type': 'text', 'text': 'hello'},
        ]);
        expect(form.files, isEmpty);
      },
    );

    test(
      'a video block carries its orientation, a photo block does not',
      () async {
        // The one thing about a file the client decides server-side: a video is
        // center-cropped to this shape during the backend's transcode, because a
        // Flutter client has no encoder. A photo is already cropped locally, so
        // sending an orientation for one would be noise the backend ignores.
        final adapter = _CapturingAdapter();
        final repo = await _repository(adapter);

        await repo.createPost(
          channelId: 1,
          blocks: [
            ComposerBlockInput.media(0),
            ComposerBlockInput.media(1, orientation: 'portrait'),
          ],
          language: 'en',
          media: [
            PickedMedia(
              bytes: Uint8List.fromList([1]),
              filename: 'a.png',
              contentType: 'image/png',
            ),
            PickedMedia(
              bytes: Uint8List.fromList([2]),
              filename: 'b.mp4',
              contentType: 'video/mp4',
            ),
          ],
        );

        final form = adapter.lastFormData!;
        final blocksField = form.fields
            .firstWhere((e) => e.key == 'blocks')
            .value;
        expect(jsonDecode(blocksField), [
          {'type': 'media', 'file_index': 0},
          {'type': 'media', 'file_index': 1, 'orientation': 'portrait'},
        ]);
      },
    );

    test('encodes a mix of text and media blocks, media by file_index', () async {
      final adapter = _CapturingAdapter();
      final repo = await _repository(adapter);

      await repo.createPost(
        channelId: 1,
        blocks: [
          ComposerBlockInput.text('intro'),
          ComposerBlockInput.media(0),
          ComposerBlockInput.media(1),
        ],
        language: 'en',
        media: [
          PickedMedia(
            bytes: Uint8List.fromList([1, 2, 3]),
            filename: 'a.jpg',
            contentType: 'image/jpeg',
          ),
          PickedMedia(
            bytes: Uint8List.fromList([4, 5, 6, 7]),
            filename: 'b.mp4',
            contentType: 'video/mp4',
          ),
        ],
      );

      final form = adapter.lastFormData!;
      final blocksField = form.fields
          .firstWhere((e) => e.key == 'blocks')
          .value;
      expect(jsonDecode(blocksField), [
        {'type': 'text', 'text': 'intro'},
        {'type': 'media', 'file_index': 0},
        {'type': 'media', 'file_index': 1},
      ]);
      // Two entries, both under the same "files" key — a single FormData.fromMap
      // entry would have collapsed them.
      expect(form.files.map((e) => e.key), ['files', 'files']);
      expect(form.files.map((e) => e.value.filename), ['a.jpg', 'b.mp4']);
      expect(form.files.map((e) => e.value.contentType?.mimeType), [
        'image/jpeg',
        'video/mp4',
      ]);
    });

    test('returns the parsed post/price/balance', () async {
      final repo = await _repository(_CapturingAdapter());
      final result = await repo.createPost(
        channelId: 1,
        blocks: [ComposerBlockInput.text('hi')],
        language: 'en',
      );

      expect(result.post.id, 1);
      expect(result.price, 3);
      expect(result.tokenBalance, 7);
    });
  });
}
