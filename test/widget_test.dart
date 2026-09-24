import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:peerkola/src/app.dart';
import 'package:peerkola/src/core/announcements/application/announcement_providers.dart';
import 'package:peerkola/src/core/announcements/data/announcement.dart';
import 'package:peerkola/src/core/network/connectivity.dart';
import 'package:peerkola/src/core/settings/app_settings.dart';
import 'package:peerkola/src/features/auth/application/auth_providers.dart';

void main() {
  testWidgets('Unauthenticated app boots and redirects to the login screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Stub auth state directly rather than touching secure storage's
          // platform channel (unavailable in widget tests).
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(loggedIn: false),
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
          // The real notifier subscribes to connectivity_plus' platform channel
          // and starts a probe timer; neither exists under flutter_test.
          connectivityProvider.overrideWith(_FakeConnectivityNotifier.new),
        ],
        child: const PeerkolaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsWidgets);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('The offline banner appears only while offline', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final connectivity = _FakeConnectivityNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(loggedIn: false),
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityProvider.overrideWith(() => connectivity),
        ],
        child: const PeerkolaApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("You're offline — reconnecting…"), findsNothing);

    // Plain pumps past the AnimatedSize, not pumpAndSettle: the offline bar
    // holds a CircularProgressIndicator, which never settles.
    connectivity.emit(ConnectionStatus.offline);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("You're offline — reconnecting…"), findsOneWidget);

    connectivity.emit(ConnectionStatus.backOnline);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Back online'), findsOneWidget);

    connectivity.emit(ConnectionStatus.online);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Back online'), findsNothing);
  });

  testWidgets('The info banner renders and can be dismissed without throwing '
      '(regression: IconButton.tooltip needs an Overlay this banner sits '
      "outside of, since it's mounted above the Navigator)", (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(loggedIn: false),
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityProvider.overrideWith(_FakeConnectivityNotifier.new),
          announcementProvider.overrideWith(
            (ref) async =>
                const Announcement(id: 'msg-1', message: 'Maintenance tonight'),
          ),
        ],
        child: const PeerkolaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Maintenance tonight'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    // The card stays mounted (transparent, ignoring pointers) through its exit
    // animation rather than vanishing instantly, so assert on the animated
    // opacity actually reaching zero rather than the text leaving the tree.
    final opacity = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('infoBannerOpacity')),
    );
    expect(opacity.opacity, 0);
  });
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier({required this.loggedIn});

  final bool loggedIn;

  @override
  Future<bool> build() async => loggedIn;
}

class _FakeConnectivityNotifier extends ConnectivityNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.online;

  void emit(ConnectionStatus status) => state = status;
}
