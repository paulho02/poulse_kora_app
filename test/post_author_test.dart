import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/src/features/feed/data/post.dart';

Map<String, dynamic> _postJson({Map<String, dynamic> author = const {}}) => {
  'id': 1,
  'channel_id': 1,
  'channel_name': 'General',
  'blocks': [
    {'type': 'text', 'text': 'hi', 'media': null},
  ],
  'is_anonymous': false,
  'author': {
    'id': 'ce1b6b1e-0000-4000-8000-000000000000',
    'username': 'ada',
    'profile_picture_url':
        '/api/v1/users/ce1b6b1e-0000-4000-8000-000000000000/profile-picture',
    ...author,
  },
  'subscription_kind': null,
  'created': DateTime.now().toUtc().toIso8601String(),
};

void main() {
  group('PostAuthor.profilePictureUrl', () {
    test('reads the backend field', () {
      final post = Post.fromJson(_postJson());
      expect(
        post.author.profilePictureUrl,
        '/api/v1/users/ce1b6b1e-0000-4000-8000-000000000000/profile-picture',
      );
    });

    test('an author with no picture reads as null', () {
      final post = Post.fromJson(
        _postJson(author: {'profile_picture_url': null}),
      );
      expect(post.author.profilePictureUrl, isNull);
      expect(post.author.username, 'ada');
    });

    test('an anonymous post carries no picture', () {
      // The backend withholds the whole author on an anonymous post (see
      // `_serialize_post`), so this asserts the client agrees rather than
      // relying on a UI-side branch to hide something that was sent anyway.
      final json = _postJson(
        author: {'id': null, 'username': null, 'profile_picture_url': null},
      )..['is_anonymous'] = true;
      final post = Post.fromJson(json);

      expect(post.isAnonymous, isTrue);
      expect(post.author.id, isNull);
      expect(post.author.username, isNull);
      expect(post.author.profilePictureUrl, isNull);
    });

    test('a response predating the field parses as no picture', () {
      // Feed responses are cached, so an entry written by an older app version
      // will simply be missing the key.
      final json = _postJson();
      (json['author'] as Map).remove('profile_picture_url');
      expect(Post.fromJson(json).author.profilePictureUrl, isNull);
    });
  });
}
