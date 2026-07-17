import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/src/app.dart';
import 'package:poulse_kora_app/src/features/auth/application/auth_providers.dart';

void main() {
  testWidgets('Unauthenticated app boots and redirects to the login screen',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // Stub auth state directly rather than touching secure storage's
        // platform channel (unavailable in widget tests).
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(loggedIn: false),
          ),
        ],
        child: const PoulseKoraApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsWidgets);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier({required this.loggedIn});

  final bool loggedIn;

  @override
  Future<bool> build() async => loggedIn;
}
