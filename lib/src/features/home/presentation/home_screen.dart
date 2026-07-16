import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/hello_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final helloMessage = ref.watch(helloMessageProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Poulse Kora')),
      body: Center(
        child: helloMessage.when(
          data: (msg) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 48),
              const SizedBox(height: 12),
              Text('Backend says: "$msg"'),
            ],
          ),
          loading: () => const CircularProgressIndicator(),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Could not reach backend:\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.invalidate(helloMessageProvider),
        tooltip: 'Retry',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
