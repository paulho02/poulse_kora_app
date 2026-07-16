import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/hello_repository.dart';

final helloRepositoryProvider = Provider<HelloRepository>((ref) {
  return HelloRepository(ref.watch(dioClientProvider).dio);
});

/// Fetches `/hello-world` from the backend. Used on the home screen as a
/// quick end-to-end check that the app can reach the API.
final helloMessageProvider = FutureProvider<String>((ref) {
  return ref.watch(helloRepositoryProvider).fetchHelloMessage();
});
