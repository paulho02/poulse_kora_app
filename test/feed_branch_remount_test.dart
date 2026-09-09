import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/src/app.dart';
import 'package:poulse_kora_app/src/core/announcements/application/announcement_providers.dart';
import 'package:poulse_kora_app/src/core/app_config/application/app_config_providers.dart';
import 'package:poulse_kora_app/src/core/cache/json_cache.dart';
import 'package:poulse_kora_app/src/core/network/connectivity.dart';
import 'package:poulse_kora_app/src/core/settings/app_settings.dart';
import 'package:poulse_kora_app/src/features/auth/application/auth_providers.dart';
import 'package:poulse_kora_app/src/features/channels/application/channels_providers.dart';
import 'package:poulse_kora_app/src/features/channels/data/channels_repository.dart';
import 'package:poulse_kora_app/src/features/economy/application/economy_providers.dart';
import 'package:poulse_kora_app/src/features/economy/data/economy_repository.dart';
import 'package:poulse_kora_app/src/features/feed/application/feed_providers.dart';
import 'package:poulse_kora_app/src/features/feed/data/feed_repository.dart';
import 'package:poulse_kora_app/src/features/feed/presentation/feed_screen.dart';
import 'package:poulse_kora_app/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:poulse_kora_app/src/features/profile/application/profile_providers.dart';
import 'package:poulse_kora_app/src/features/profile/data/profile_repository.dart';

/// The post-registration route sequence, end to end: `/feed` mounts first
/// (the profile fetch is still in flight, and the redirect deliberately fails
/// open), the profile then says onboarding is incomplete and the redirect
/// tears `/feed` down, and finishing onboarding sends the shell back to it.
///
/// The regression this pins is that last step. `FeedScreen.dispose` used to
/// `ref.read` the feed notifier, which Riverpod answers from an unmounting
/// widget by throwing — and an exception thrown mid-unmount aborts the
/// framework's unmount pass, leaving the feed branch's elements defunct with
/// their `GlobalKey`s still registered. Re-activating that branch then failed
/// and the whole tab rendered as an `ErrorWidget`: a blank body under a
/// perfectly working navigation bar, which is what a new account saw the
/// moment onboarding ended.
void main() {
  testWidgets('the feed survives being disposed by a redirect and remounted', (
    tester,
  ) async {
    final backend = _FakeBackend();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = JsonCache(prefs);
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    dio.httpClientAdapter = backend;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authNotifierProvider.overrideWith(_FakeAuth.new),
          connectivityProvider.overrideWith(_FakeConnectivity.new),
          profileRepositoryProvider.overrideWithValue(
            ProfileRepository(dio, cache),
          ),
          channelsRepositoryProvider.overrideWithValue(
            ChannelsRepository(dio, cache),
          ),
          feedRepositoryProvider.overrideWithValue(FeedRepository(dio, cache)),
          economyRepositoryProvider.overrideWithValue(
            EconomyRepository(dio, cache),
          ),
          appConfigProvider.overrideWith((ref) async => null),
          announcementProvider.overrideWith((ref) async => null),
        ],
        child: const PoulseKoraApp(),
      ),
    );

    // `/feed` is the initial location and the profile has not landed yet, so
    // this is the state the redirect lets through.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FeedScreen), findsOneWidget);

    // The profile lands: onboarding is incomplete, so the redirect replaces the
    // shell with the onboarding flow and disposes the feed. Plain pumps, never
    // `pumpAndSettle` — the onboarding illustrations animate forever.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Finish onboarding, exactly as the flow's last step does.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    // Not awaited: the fake backend answers on the test's fake clock, which only
    // advances on `pump`, so awaiting the call here would deadlock the test.
    container.read(profileProvider.notifier).completeOnboarding().ignore();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(FeedScreen), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// Just enough backend for the post-registration route sequence.
class _FakeBackend implements HttpClientAdapter {
  bool onboardingCompleted = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    switch (options.path) {
      case '/users/me':
        if (options.method == 'PATCH') {
          final body = options.data as Map<String, dynamic>;
          onboardingCompleted =
              body['onboarding_completed'] as bool? ?? onboardingCompleted;
          return _json(_profile());
        }
        // Deliberately slower than the first frame: the feed has to mount
        // before the redirect knows about onboarding, which is the whole
        // sequence under test.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return _json(_profile());
      case '/channels':
        return _json([
          {
            'id': 1,
            'name': 'General',
            'color': '#6B7280',
            'description': 'Everything and anything',
            'is_subscribed': true,
            'post_price': 1,
          },
        ]);
      case '/posts/feed':
        return _json(const []);
      case '/posts/feed/status':
        return _json({'post_ids': const [], 'capacity': 20});
      case '/posts/economy':
        return _json({'token_balance': 10, 'post_price': 1});
      default:
        throw StateError('unexpected request: ${options.path}');
    }
  }

  Map<String, dynamic> _profile() => {
    'id': '00000000-0000-0000-0000-000000000001',
    'email': 'new@example.com',
    'username': 'newcomer',
    'bio': null,
    'dark_mode': false,
    'settings_revision': 0,
    'onboarding_completed': onboardingCompleted,
    'is_verified': true,
    'auth_provider': 'password',
    'google_email': null,
    'profile_picture_url': null,
  };

  static ResponseBody _json(Object body) => ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      'content-type': ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _FakeAuth extends AuthNotifier {
  @override
  Future<bool> build() async => true;
}

class _FakeConnectivity extends ConnectivityNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.online;
}
