import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/src/features/feed/data/post.dart';

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
      'forwarded_count': 0,
      'dropped_count': 0,
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
