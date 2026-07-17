import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/profile_repository.dart';
import '../data/user_profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(dioClientProvider).dio);
});

class ProfileNotifier extends AsyncNotifier<UserProfile> {
  @override
  Future<UserProfile> build() {
    return ref.read(profileRepositoryProvider).fetchMe();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(profileRepositoryProvider).fetchMe());
  }

  Future<void> toggleDarkMode() async {
    final current = state.value;
    if (current == null) return;
    final optimistic = current.copyWith(darkMode: !current.darkMode);
    state = AsyncData(optimistic);
    try {
      final updated =
          await ref.read(profileRepositoryProvider).updateMe(darkMode: optimistic.darkMode);
      state = AsyncData(updated);
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }

  Future<void> updateBio(String bio) async {
    final current = state.value;
    if (current == null) return;
    final updated = await ref.read(profileRepositoryProvider).updateMe(bio: bio);
    state = AsyncData(updated);
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, UserProfile>(
  ProfileNotifier.new,
);
