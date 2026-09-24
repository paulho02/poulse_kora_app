import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/core/app_config/data/public_app_config.dart';
import 'package:peerkola/src/features/channels/data/channel.dart';
import 'package:peerkola/src/features/create_post/presentation/language_picker_sheet.dart';
import 'package:peerkola/src/features/economy/data/economy.dart';
import 'package:peerkola/src/features/profile/data/user_profile.dart';

/// Language routing, client side. Four things here fail *silently* rather than
/// loudly, which is why each has a test:
///
/// - a post published under the wrong language reaches people who cannot read
///   it, and nothing on either side reports an error;
/// - "no language" claimed by a post that has text buys the widest audience in
///   the app, and the composer is the only place that can catch it before an
///   upload is spent;
/// - a price range read as a single number, or vice versa, shows a figure
///   nobody is charged;
/// - a stale payload from a backend that predates any of this must degrade to
///   the old behaviour rather than to an exception.
void main() {
  group('PublicAppConfig', () {
    test('reads the content languages the backend accepts', () {
      final config = PublicAppConfig.fromJson(const {
        'require_email_verification': true,
        'require_strong_password': false,
        'password_min_length': 10,
        'password_min_character_classes': 3,
        'email_verification_resend_cooldown_seconds': 60,
        'google_oauth_enabled': false,
        'content_languages': ['en', 'de', 'fr'],
        'language_unspecified': 'und',
      });

      expect(config.contentLanguages, ['en', 'de', 'fr']);
      expect(config.languageUnspecified, 'und');
    });

    test('falls back when the backend predates language routing', () {
      // Guessing a *wider* list here would only produce posts the backend
      // refuses, so the fallback is what this app ships copy for.
      final config = PublicAppConfig.fromJson(const {
        'require_email_verification': true,
        'require_strong_password': false,
        'password_min_length': 10,
        'password_min_character_classes': 3,
        'email_verification_resend_cooldown_seconds': 60,
      });

      expect(config.contentLanguages, ['en', 'de']);
      expect(config.languageUnspecified, 'und');
    });
  });

  group('UserProfile.contentLanguages', () {
    test('reads the accepted set', () {
      expect(_profileJson(languages: ['de']).contentLanguages, ['de']);
    });

    test('defaults wide on a payload written before the field existed', () {
      // The backend migration widened these accounts too, so anything narrower
      // would show a settings screen contradicting what the feed delivers.
      expect(_profileJson().contentLanguages, ['en', 'de']);
    });
  });

  group('Channel price range', () {
    test('reads both ends', () {
      final channel = _channelJson(min: 2, max: 6);
      expect(channel.postPriceMin, 2);
      expect(channel.postPriceMax, 6);
      expect(channel.hasSinglePrice, isFalse);
      // The affordability check uses the low end: refusing someone a post that
      // a different language would make affordable is a no they cannot act on.
      expect(channel.lowestPrice, 2);
    });

    test('a collapsed range is a single price', () {
      expect(_channelJson(min: 4, max: 4).hasSinglePrice, isTrue);
    });

    test('an absent range stays unknown, never free', () {
      final channel = Channel.fromJson(const {
        'id': 1,
        'name': 'Music',
        'color': '#ff0000',
        'description': 'Songs',
        'is_subscribed': true,
      });
      expect(channel.postPriceMin, isNull);
      expect(channel.lowestPrice, isNull);
    });

    test('survives a subscription toggle', () {
      final toggled = _channelJson(min: 2, max: 6).copyWith(isSubscribed: false);
      expect(toggled.postPriceMin, 2);
      expect(toggled.postPriceMax, 6);
    });
  });

  group('Economy price range', () {
    test('reports the observed spread', () {
      final economy = _economy(price: 4, min: 2, max: 6);
      expect(economy.priceRange, (2, 6));
      expect(economy.hasSinglePrice, isFalse);
    });

    test('falls back to the base price at both ends', () {
      // What the backend itself reports before any route has been priced in the
      // current window, and what a cache entry predating this looks like.
      final economy = _economy(price: 4);
      expect(economy.priceRange, (4, 4));
      expect(economy.hasSinglePrice, isTrue);
    });

    test('affordability is judged against the cheapest route', () {
      final economy = _economy(price: 6, min: 2, max: 6);
      expect(
        economy.copyWith(tokenBalance: 3).canAffordPost,
        isTrue,
        reason: 'a 3-token balance affords the 2-token route',
      );
      expect(economy.copyWith(tokenBalance: 1).canAffordPost, isFalse);
    });
  });

  group('language picker sheet', () {
    testWidgets('offers "no language" for a post with no text', (tester) async {
      await _pumpPicker(tester, allowUnspecified: true);

      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('No language'),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.enabled, isTrue);
      expect(find.textContaining('photo or a clip'), findsOneWidget);
    });

    testWidgets('disables "no language" once the post has text', (
      tester,
    ) async {
      // Greyed out with a reason rather than hidden: an author who expected the
      // option learns why it is gone instead of hunting for it.
      await _pumpPicker(tester, allowUnspecified: false);

      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('No language'),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.enabled, isFalse);
      expect(find.text('Only for posts without text'), findsOneWidget);
    });

    testWidgets('badges the detector suggestion without selecting it', (
      tester,
    ) async {
      await _pumpPicker(tester, allowUnspecified: true, suggested: 'de');

      expect(find.text('Suggested'), findsOneWidget);
      // Badged on German, but English stays the selection — the picker is open
      // precisely because someone wants to decide for themselves.
      final german = find.ancestor(
        of: find.text('German'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: german, matching: find.byIcon(Icons.check)),
        findsNothing,
      );
    });

    testWidgets('says what the choice actually decides', (tester) async {
      // Without this line a language picker on a composer reads as spell-check
      // settings rather than as the thing that decides who receives the post.
      await _pumpPicker(tester, allowUnspecified: true);
      expect(find.textContaining('who gets your post'), findsOneWidget);
    });
  });
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  required bool allowUnspecified,
  String? suggested,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showLanguagePickerSheet(
                context,
                selected: 'en',
                allowUnspecified: allowUnspecified,
                suggested: suggested,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

UserProfile _profileJson({List<String>? languages}) =>
    UserProfile.fromJson(<String, dynamic>{
      'id': 'u1',
      'email': 'a@b.c',
      'username': 'someone',
      'bio': null,
      'dark_mode': false,
      'is_verified': true,
      'profile_picture_url': null,
      'content_languages': ?languages,
    });

Channel _channelJson({required int min, required int max}) =>
    Channel.fromJson(<String, dynamic>{
      'id': 1,
      'name': 'Music',
      'color': '#ff0000',
      'description': 'Songs',
      'is_subscribed': true,
      'post_price_min': min,
      'post_price_max': max,
    });

Economy _economy({required int price, int? min, int? max}) => Economy(
  tokenBalance: 0,
  postPrice: price,
  postPriceMin: min,
  postPriceMax: max,
);
