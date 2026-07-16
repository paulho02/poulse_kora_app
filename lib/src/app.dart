import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/app_router.dart';

class PoulseKoraApp extends ConsumerWidget {
  const PoulseKoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Poulse Kora',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      routerConfig: router,
    );
  }
}
