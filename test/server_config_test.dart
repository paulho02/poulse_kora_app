import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/src/core/config/app_config.dart';
import 'package:poulse_kora_app/src/core/config/server_config.dart';

/// `CUSTOM_SERVER_ENABLED` is a compile-time `--dart-define`, so these run
/// against whatever the build under test was given — `flutter test` passes
/// none, which is the shipped MVP configuration (off). The assertions are
/// written both ways rather than pinned to "off" so the suite still means
/// something under `flutter test --dart-define=CUSTOM_SERVER_ENABLED=true`.
void main() {
  const enabled = AppConfig.customServerEnabled;

  group('ServerConfigStore', () {
    test('a stored override is only honoured while the flag is on', () async {
      SharedPreferences.setMockInitialValues({
        'server.customBaseUrl': 'https://self.hosted.example',
      });
      final store = ServerConfigStore(await SharedPreferences.getInstance());

      final config = store.read();
      if (enabled) {
        expect(config.isCustom, isTrue);
        expect(config.baseUrl, 'https://self.hosted.example');
      } else {
        // The point of the guard: an install that saved a custom URL under an
        // earlier build must fall back to the official server, not keep
        // talking to a backend it has no UI left to change.
        expect(config.isCustom, isFalse);
        expect(config.baseUrl, AppConfig.apiBaseUrl);
      }
    });

    test('the stored key survives the flag being off', () async {
      SharedPreferences.setMockInitialValues({
        'server.customBaseUrl': 'https://self.hosted.example',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = ServerConfigStore(prefs);

      await store.write('https://other.example');

      // Turning the flag back on restores the user's previous choice, so a
      // disabled build must not quietly rewrite or clear the key.
      expect(
        prefs.getString('server.customBaseUrl'),
        enabled ? 'https://other.example' : 'https://self.hosted.example',
      );
    });
  });

  group('server URL helpers', () {
    test('normalizeServerUrl trims and drops a trailing slash', () {
      expect(normalizeServerUrl('  https://a.example/  '), 'https://a.example');
      expect(normalizeServerUrl('https://a.example'), 'https://a.example');
    });

    test('isValidServerUrl requires an http(s) scheme and a host', () {
      expect(isValidServerUrl('https://a.example'), isTrue);
      expect(isValidServerUrl('http://a.example:8000'), isTrue);
      expect(isValidServerUrl('a.example'), isFalse);
      expect(isValidServerUrl('ftp://a.example'), isFalse);
      expect(isValidServerUrl('https://'), isFalse);
    });
  });
}
