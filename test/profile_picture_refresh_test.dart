import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/l10n/generated/app_localizations.dart';
import 'package:poulse_kora_app/src/core/cache/json_cache.dart';
import 'package:poulse_kora_app/src/core/media/presentation/network_media_image.dart';
import 'package:poulse_kora_app/src/core/settings/app_settings.dart';
import 'package:poulse_kora_app/src/features/profile/application/profile_providers.dart';
import 'package:poulse_kora_app/src/features/profile/data/profile_repository.dart';
import 'package:poulse_kora_app/src/features/profile/presentation/editable_profile_avatar.dart';

/// Stands in for the backend: answers `/users/me` with whatever picture URL it
/// currently holds, and treats `PUT .../profile-picture` as having installed a
/// new one — mirroring the real route, which writes a fresh random object key
/// per upload and so hands back a URL that has genuinely changed.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.url);

  String? url;
  int uploads = 0;
  int profileGets = 0;

  Map<String, dynamic> get _profile => {
    'id': 'ce1b6b1e-0000-4000-8000-000000000000',
    'email': 'ada@example.com',
    'username': 'ada',
    'bio': null,
    'dark_mode': false,
    'settings_revision': 3,
    'onboarding_completed': true,
    'is_verified': true,
    'auth_provider': 'password',
    'google_email': null,
    'profile_picture_url': url,
    'content_languages': ['en'],
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('profile-picture')) {
      uploads++;
      // What the real backend does: a new random object key per upload, so a
      // replaced picture is a different URL.
      url = 'https://bucket.example/pic-$uploads.jpg?sig=$uploads';
    } else {
      profileGets++;
    }
    return ResponseBody.fromString(
      jsonEncode(_profile),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The URL the avatar is currently pointed at.
///
/// Read off [NetworkMediaImage] rather than off the `Image` it builds: an
/// `Image.network` whose fetch fails replaces itself with its `errorBuilder`
/// (here, the monogram), and in a widget test every fetch fails. What is under
/// test is which URL the widget was *given*, which is exactly this.
List<String> renderedImageUrls(WidgetTester tester) => tester
    .widgetList<NetworkMediaImage>(find.byType(NetworkMediaImage))
    .map((image) => image.url)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Adapter adapter;
  late ProviderContainer container;
  late SharedPreferences prefs;

  Future<ProfileRepository> buildRepository() async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example/api/v1'))
      ..httpClientAdapter = adapter;
    return ProfileRepository(dio, JsonCache(prefs));
  }

  List<dynamic> overrides(ProfileRepository repository) => [
    sharedPreferencesProvider.overrideWithValue(prefs),
    profileRepositoryProvider.overrideWithValue(repository),
  ];

  Future<void> pumpProfileAvatar(WidgetTester tester) async {
    final repository = await buildRepository();
    container = ProviderContainer(overrides: overrides(repository).cast());
    addTearDown(container.dispose);

    // `runAsync` because the first load goes through Dio, whose futures do not
    // resolve under the test binding's fake clock — `pump()` alone leaves the
    // provider in `AsyncLoading` forever.
    await tester.runAsync(() => container.read(profileProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final profile = ref.watch(profileProvider);
                return profile.when(
                  data: (cached) =>
                      EditableProfileAvatar(profile: cached.data),
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => Text('$e'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() async {
    adapter = _Adapter('https://bucket.example/pic-0.jpg?sig=0');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('the avatar paints the picture the profile arrived with', (
    tester,
  ) async {
    await pumpProfileAvatar(tester);
    expect(renderedImageUrls(tester), ['https://bucket.example/pic-0.jpg?sig=0']);
  });

  testWidgets('uploading a new picture repaints the avatar', (tester) async {
    await pumpProfileAvatar(tester);

    await tester.runAsync(
      () => container
          .read(profileProvider.notifier)
          .setProfilePicture(
            bytes: const [1, 2, 3],
            filename: 'avatar.png',
            contentType: 'image/png',
          ),
    );
    await tester.pump();

    expect(adapter.uploads, 1);
    expect(renderedImageUrls(tester), ['https://bucket.example/pic-1.jpg?sig=1']);
  });

  testWidgets('a restart re-reads the picture from the server', (tester) async {
    await pumpProfileAvatar(tester);
    await tester.runAsync(
      () => container
          .read(profileProvider.notifier)
          .setProfilePicture(
            bytes: const [1, 2, 3],
            filename: 'avatar.png',
            contentType: 'image/png',
          ),
    );
    await tester.pump();

    // A cold start: a brand-new container over the same (already-uploaded)
    // server state, which is what "restarting the app" is.
    final repository = await buildRepository();
    final restarted = ProviderContainer(overrides: overrides(repository).cast());
    addTearDown(restarted.dispose);
    final profile = await tester.runAsync(
      () => restarted.read(profileProvider.future),
    );

    expect(
      profile!.data.profilePictureUrl,
      'https://bucket.example/pic-1.jpg?sig=1',
    );
  });
}
