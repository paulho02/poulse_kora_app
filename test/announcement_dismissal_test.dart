import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/src/core/announcements/application/announcement_providers.dart';
import 'package:poulse_kora_app/src/core/announcements/data/announcement.dart';
import 'package:poulse_kora_app/src/core/settings/app_settings.dart';

/// Covers the two independent dismissal lifetimes described in
/// `AnnouncementForeverDismissalNotifier` / `AnnouncementSessionDismissalNotifier`,
/// and how `visibleAnnouncementProvider` combines them with a fetched id.
void main() {
  late ProviderContainer container;

  Future<ProviderContainer> makeContainer({
    Map<String, Object> initialPrefs = const {},
    Announcement? fetched,
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        announcementProvider.overrideWith((ref) async => fetched),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('AnnouncementForeverDismissalNotifier', () {
    test('starts null with nothing persisted', () async {
      container = await makeContainer();
      expect(container.read(announcementForeverDismissalProvider), isNull);
    });

    test('a forever-dismissal survives a restart', () async {
      container = await makeContainer();
      await container
          .read(announcementForeverDismissalProvider.notifier)
          .dismissForever('msg-1');
      container.dispose();

      // Same underlying prefs, fresh container — as if the app were relaunched.
      final prefs = await SharedPreferences.getInstance();
      final restarted = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          announcementProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(restarted.dispose);

      expect(restarted.read(announcementForeverDismissalProvider), 'msg-1');
    });
  });

  group('AnnouncementSessionDismissalNotifier', () {
    test('a session dismissal never survives a restart', () async {
      container = await makeContainer();
      container
          .read(announcementSessionDismissalProvider.notifier)
          .dismiss('msg-1');
      expect(container.read(announcementSessionDismissalProvider), 'msg-1');
      container.dispose();

      final prefs = await SharedPreferences.getInstance();
      final restarted = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          announcementProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(restarted.dispose);

      expect(restarted.read(announcementSessionDismissalProvider), isNull);
    });
  });

  group('visibleAnnouncementProvider', () {
    test(
      'shows a freshly fetched announcement with no dismissal on record',
      () async {
        container = await makeContainer(
          fetched: const Announcement(id: 'msg-1', message: 'hi'),
        );
        await container.read(announcementProvider.future);

        expect(container.read(visibleAnnouncementProvider)?.id, 'msg-1');
      },
    );

    test('hides an announcement whose id was dismissed forever', () async {
      container = await makeContainer(
        initialPrefs: {'announcement.dismissedForeverId': 'msg-1'},
        fetched: const Announcement(id: 'msg-1', message: 'hi'),
      );
      await container.read(announcementProvider.future);

      expect(container.read(visibleAnnouncementProvider), isNull);
    });

    test('hides an announcement dismissed for this session', () async {
      container = await makeContainer(
        fetched: const Announcement(id: 'msg-1', message: 'hi'),
      );
      await container.read(announcementProvider.future);
      container
          .read(announcementSessionDismissalProvider.notifier)
          .dismiss('msg-1');

      expect(container.read(visibleAnnouncementProvider), isNull);
    });

    test(
      'a new id is shown despite an old id being dismissed forever',
      () async {
        container = await makeContainer(
          initialPrefs: {'announcement.dismissedForeverId': 'msg-1'},
          fetched: const Announcement(id: 'msg-2', message: 'a new notice'),
        );
        await container.read(announcementProvider.future);

        expect(container.read(visibleAnnouncementProvider)?.id, 'msg-2');
      },
    );

    test('shows nothing when no announcement is set', () async {
      container = await makeContainer();
      await container.read(announcementProvider.future);

      expect(container.read(visibleAnnouncementProvider), isNull);
    });
  });
}
