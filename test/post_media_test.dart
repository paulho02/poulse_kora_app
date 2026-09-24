import 'package:flutter_test/flutter_test.dart';

import 'package:peerkola/src/features/feed/data/post.dart';

void main() {
  group('PostMedia.fromJson', () {
    test('parses an image entry', () {
      final media = PostMedia.fromJson({
        'id': 1,
        'media_type': 'image',
        'content_type': 'image/jpeg',
        'url': '/api/v1/posts/1/media/1',
        'duration_seconds': null,
      });
      expect(media.isVideo, isFalse);
      expect(media.contentType, 'image/jpeg');
      expect(media.durationSeconds, isNull);
    });

    test('parses a video entry with a duration', () {
      final media = PostMedia.fromJson({
        'id': 2,
        'media_type': 'video',
        'content_type': 'video/mp4',
        'url': '/api/v1/posts/1/media/2',
        'duration_seconds': 12.5,
      });
      expect(media.isVideo, isTrue);
      expect(media.durationSeconds, 12.5);
    });

    test('dimensions become the aspect ratio a block is laid out at', () {
      final media = PostMedia.fromJson({
        'id': 3,
        'media_type': 'image',
        'content_type': 'image/jpeg',
        'url': '/a',
        'duration_seconds': null,
        'width': 1024,
        'height': 1280,
      });
      expect(media.aspectRatio, closeTo(0.8, 0.0001));
    });

    test('media from before dimensions existed reports an unknown shape', () {
      // Old rows are not backfilled and may be any shape, so callers letterbox
      // rather than assuming one of the two fixed ratios — null is the signal
      // that makes that possible, and must not become a default.
      final media = PostMedia.fromJson({
        'id': 4,
        'media_type': 'image',
        'content_type': 'image/jpeg',
        'url': '/a',
        'duration_seconds': null,
      });
      expect(media.aspectRatio, isNull);
    });

    test('a zero dimension is treated as unknown, not as a ratio', () {
      final media = PostMedia.fromJson({
        'id': 5,
        'media_type': 'image',
        'content_type': 'image/jpeg',
        'url': '/a',
        'duration_seconds': null,
        'width': 0,
        'height': 0,
      });
      expect(media.aspectRatio, isNull);
    });

    test(
      'previewUrl is the poster for video and the file itself for a photo',
      () {
        final video = PostMedia.fromJson({
          'id': 6,
          'media_type': 'video',
          'content_type': 'video/mp4',
          'url': '/media/6',
          'duration_seconds': 3.0,
          'poster_url': '/media/6/poster',
        });
        expect(video.previewUrl, '/media/6/poster');

        final photo = PostMedia.fromJson({
          'id': 7,
          'media_type': 'image',
          'content_type': 'image/jpeg',
          'url': '/media/7',
          'duration_seconds': null,
        });
        expect(photo.previewUrl, '/media/7');
      },
    );

    test('a video whose poster extraction failed has nothing to preview', () {
      // Extraction is deliberately non-fatal server-side, so this is a state
      // the UI has to render (a neutral tile), not an error.
      final media = PostMedia.fromJson({
        'id': 8,
        'media_type': 'video',
        'content_type': 'video/mp4',
        'url': '/media/8',
        'duration_seconds': 3.0,
        'poster_url': null,
      });
      expect(media.previewUrl, isNull);
    });
  });

  group('PostBlock.fromJson', () {
    test('parses a text block', () {
      final block = PostBlock.fromJson({'type': 'text', 'text': 'hello'});
      expect(block, isA<PostTextBlock>());
      expect((block as PostTextBlock).text, 'hello');
    });

    test('parses a media block', () {
      final block = PostBlock.fromJson({
        'type': 'media',
        'text': null,
        'media': {
          'id': 1,
          'media_type': 'image',
          'content_type': 'image/jpeg',
          'url': '/a',
          'duration_seconds': null,
        },
      });
      expect(block, isA<PostMediaBlock>());
      expect((block as PostMediaBlock).media.id, 1);
    });
  });

  group('Post', () {
    Map<String, dynamic> postJson(List<Map<String, dynamic>> blocks) => {
      'id': 1,
      'channel_id': 1,
      'channel_name': 'General',
      'blocks': blocks,
      'is_anonymous': false,
      'author': {'id': null, 'username': null, 'profile_picture_url': null},
      'subscription_kind': null,
      'created': DateTime.now().toUtc().toIso8601String(),
    };

    Map<String, dynamic> textBlock(String text) => {
      'type': 'text',
      'text': text,
      'media': null,
    };

    Map<String, dynamic> mediaBlock(int id) => {
      'type': 'media',
      'text': null,
      'media': {
        'id': id,
        'media_type': 'image',
        'content_type': 'image/jpeg',
        'url': '/media/$id',
        'duration_seconds': null,
      },
    };

    test('hasMedia is false with no media blocks', () {
      expect(Post.fromJson(postJson([textBlock('hi')])).hasMedia, isFalse);
    });

    test('mediaItems reflects the media blocks, in block order', () {
      final post = Post.fromJson(
        postJson([textBlock('intro'), mediaBlock(1), mediaBlock(2)]),
      );
      expect(post.hasMedia, isTrue);
      expect(post.mediaItems.map((m) => m.id), [1, 2]);
    });

    test('previewText joins every text block, skipping media blocks', () {
      final post = Post.fromJson(
        postJson([
          textBlock('first paragraph'),
          mediaBlock(1),
          textBlock('second paragraph'),
        ]),
      );
      expect(post.previewText, 'first paragraph second paragraph');
    });

    test('blocks preserve the exact order the server sent', () {
      final post = Post.fromJson(
        postJson([mediaBlock(1), textBlock('caption')]),
      );
      expect(post.blocks, [isA<PostMediaBlock>(), isA<PostTextBlock>()]);
    });
  });
}
