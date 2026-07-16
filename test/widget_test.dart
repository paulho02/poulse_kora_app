import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/src/app.dart';
import 'package:poulse_kora_app/src/features/home/application/hello_providers.dart';

void main() {
  testWidgets('App boots and shows the home app bar', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // Avoid a real network call (and its pending Dio timer) in the
        // widget test by stubbing the backend response.
        overrides: [
          helloMessageProvider.overrideWith((ref) async => 'Hello world!'),
        ],
        child: const PoulseKoraApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Poulse Kora'), findsOneWidget);
    expect(find.text('Backend says: "Hello world!"'), findsOneWidget);
  });
}
