import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/src/app.dart';
import 'package:poulse_kora_app/src/core/network/connectivity.dart';
import 'package:poulse_kora_app/src/core/settings/app_settings.dart';
import 'package:poulse_kora_app/src/features/auth/application/auth_providers.dart';

void main() {
  testWidgets('Unauthenticated app boots and redirects to the login screen',
      (tester) async {
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
        child: const PoulseKoraApp(),
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
        child: const PoulseKoraApp(),
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
