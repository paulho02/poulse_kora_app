import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/src/features/feed/data/post.dart';

Post _postCreatedAgo(Duration ago) => Post(
  id: 1,
  channelId: 1,
  channelName: 'General',
  text: 'hi',
  hasImage: false,
  isAnonymous: false,
  author: PostAuthor(id: 'u1', username: 'ada', profilePictureUrl: null),
  forwardedCount: 0,
  droppedCount: 0,
  subscriptionKind: null,
  created: DateTime.now().toUtc().subtract(ago),
);

void main() {
  group('Post.timeAgo', () {
    test('a post from this minute reads "now"', () {
      expect(_postCreatedAgo(const Duration(seconds: 10)).timeAgo, 'now');
    });

    test('minutes old reads in minutes', () {
      expect(_postCreatedAgo(const Duration(minutes: 5)).timeAgo, '5m');
    });

    test('hours old reads in hours', () {
      expect(_postCreatedAgo(const Duration(hours: 3)).timeAgo, '3h');
    });

    test('a day or more old reads in days', () {
      expect(_postCreatedAgo(const Duration(days: 2)).timeAgo, '2d');
    });
  });

  group('Post.timeRemaining / deadlineProgress', () {
    test('a fresh post has nearly a full 24h window left', () {
      final post = _postCreatedAgo(Duration.zero);
      // `inHours` truncates, and `created` is stamped from the clock a moment
      // before this runs — so the exact value is 24 only when literally zero
      // time has passed, and 23 otherwise. Asserting 24 made this test fail
      // whenever the machine was busy enough to lose a microsecond here.
      expect(post.timeRemaining.inHours, anyOf(23, 24));
      expect(post.timeRemaining, greaterThan(const Duration(hours: 23)));
      expect(post.deadlineProgress, closeTo(0, 0.01));
    });

    test('a post past the 24h window has nothing left, clamped', () {
      final post = _postCreatedAgo(const Duration(hours: 30));
      expect(post.timeRemaining, Duration.zero);
      expect(post.deadlineProgress, 1.0);
    });
  });
}
