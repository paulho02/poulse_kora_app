import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/dio_client.dart';
import 'storage/token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final dioClientProvider = Provider<DioClient>((ref) {
  return DioClient(ref.watch(tokenStorageProvider));
});
