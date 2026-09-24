import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/core/media/post_media_format.dart';
import 'package:peerkola/src/features/channels/data/channel.dart';
import 'package:peerkola/src/features/create_post/presentation/post_preview.dart';
import 'package:peerkola/src/features/feed/data/post.dart';
import 'package:peerkola/src/features/profile/data/user_profile.dart';

/// The composer's preview draws the post with the **reader's** widgets, from
/// bytes that have not been uploaded yet. Two things could break silently and
/// are what this file pins: the assembled [Post] must say what the reader will
/// actually be told (anonymity above all), and a local attachment must render
/// from its bytes rather than reaching for a URL that does not exist.

/// A real 1x1 PNG. Decoding never completes under a widget test's fake clock
/// (see `network_media_image_test.dart`), so nothing here asserts pixels — but
/// giving `Image.memory` valid bytes keeps a decode failure from being the
/// reason a test goes red.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
    'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
);

UserProfile _profile() => UserProfile(
  id: 'u1',
  email: 'a@b.c',
  username: 'writer',
  bio: null,
  darkMode: false,
  settingsRevision: 0,
  onboardingCompleted: true,
  isVerified: true,
  authProvider: 'password',
  googleEmail: null,
  profilePictureUrl: null,
  contentLanguages: const ['en', 'de'],
);

Channel _channel() => Channel(
  id: 7,
  name: 'Ideas',
  color: '#4488cc',
  description: '',
  isSubscribed: true,
);

Widget _host(Post post) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => showPostPreview(context, post),
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _openPreview(WidgetTester tester, Post post) async {
  await tester.pumpWidget(_host(post));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('PostMedia.local', () {
    test('carries its bytes and the shape it will publish in', () {
      final media = PostMedia.local(
        bytes: _png,
        isVideo: false,
        aspectRatio: kPostMediaPortraitRatio,
      );
      expect(media.isLocal, isTrue);
      expect(media.localBytes, same(_png));
      expect(media.aspectRatio, closeTo(kPostMediaPortraitRatio, 0.001));
    });

    test('has no URL and no poster to reach for', () {
      // Nothing has been uploaded, so a caller that used `url` or `previewUrl`
      // instead of branching on `isLocal` would be requesting nothing.
      final media = PostMedia.local(
        bytes: _png,
        isVideo: true,
        aspectRatio: kPostMediaLandscapeRatio,
      );
      expect(media.url, isEmpty);
      expect(media.posterUrl, isNull);
      expect(media.isVideo, isTrue);
    });
  });

  group('buildPreviewPost', () {
    test('shows the author the reader would see', () {
      final post = buildPreviewPost(
        blocks: [PostTextBlock('hello')],
        channel: _channel(),
        isAnonymous: false,
        author: _profile(),
      );
      expect(post.author.username, 'writer');
      expect(post.channelName, 'Ideas');
      expect(post.isAnonymous, isFalse);
    });

    test('an anonymous preview is anonymous', () {
      // The rule this protects is the whole point of previewing anonymity: the
      // real post carries no author at all, so a preview that quietly showed
      // one would be reassuring about the wrong thing.
      final post = buildPreviewPost(
        blocks: [PostTextBlock('hello')],
        channel: _channel(),
        isAnonymous: true,
        author: _profile(),
      );
      expect(post.isAnonymous, isTrue);
    });

    test('survives having no channel picked yet', () {
      final post = buildPreviewPost(
        blocks: [PostTextBlock('hello')],
        channel: null,
        isAnonymous: false,
        author: null,
      );
      expect(post.channelName, isEmpty);
      expect(post.author.username, isNull);
    });
  });

  group('the preview page', () {
    testWidgets('renders the post and names itself a preview', (tester) async {
      await _openPreview(
        tester,
        buildPreviewPost(
          blocks: [PostTextBlock('a thought worth relaying')],
          channel: _channel(),
          isAnonymous: false,
          author: _profile(),
        ),
      );

      expect(find.text('a thought worth relaying'), findsOneWidget);
      expect(find.text('writer'), findsOneWidget);
      expect(find.textContaining('Ideas'), findsOneWidget);
      expect(find.textContaining('Preview'), findsOneWidget);
    });

    testWidgets('the verdict buttons are shown, inert', (tester) async {
      await _openPreview(
        tester,
        buildPreviewPost(
          blocks: [PostTextBlock('hello')],
          channel: _channel(),
          isAnonymous: false,
          author: _profile(),
        ),
      );

      // Present, because they take the bottom of the screen away from the
      // article and previewing without them would preview more room than the
      // post gets — and disabled, because there is nothing to review yet.
      for (final label in ['Drop', 'Forward']) {
        final button = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(FilledButton),
          ),
        );
        expect(button.onPressed, isNull, reason: '$label must be inert');
      }
    });

    testWidgets('an anonymous preview withholds the name', (tester) async {
      await _openPreview(
        tester,
        buildPreviewPost(
          blocks: [PostTextBlock('hello')],
          channel: _channel(),
          isAnonymous: true,
          author: _profile(),
        ),
      );

      expect(find.text('writer'), findsNothing);
      expect(find.text('Anonymous'), findsOneWidget);
    });

    testWidgets('a picked photo is drawn from its bytes', (tester) async {
      await _openPreview(
        tester,
        buildPreviewPost(
          blocks: [
            PostMediaBlock(
              PostMedia.local(
                bytes: _png,
                isVideo: false,
                aspectRatio: kPostMediaLandscapeRatio,
              ),
            ),
          ],
          channel: _channel(),
          isAnonymous: false,
          author: _profile(),
        ),
      );

      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(AspectRatio),
          matching: find.byType(Image),
        ),
      );
      expect(image.image, isA<MemoryImage>());
    });

    testWidgets('a picked clip stands in for itself rather than playing', (
      tester,
    ) async {
      // The crop, the transcode and the poster frame are all still the
      // server's to do, so playing the raw file would preview a shape the
      // reader will never see.
      await _openPreview(
        tester,
        buildPreviewPost(
          blocks: [
            PostMediaBlock(
              PostMedia.local(
                bytes: _png,
                isVideo: true,
                aspectRatio: kPostMediaPortraitRatio,
              ),
            ),
          ],
          channel: _channel(),
          isAnonymous: false,
          author: _profile(),
        ),
      );

      expect(find.textContaining('Your video plays here'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      // The block still reserves the shape the clip will publish in.
      final ratios = tester
          .widgetList<AspectRatio>(find.byType(AspectRatio))
          .map((w) => w.aspectRatio);
      expect(ratios, contains(closeTo(kPostMediaPortraitRatio, 0.001)));
    });
  });
}
