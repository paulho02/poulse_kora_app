import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/channel.dart';
import '../data/channels_repository.dart';

final channelsRepositoryProvider = Provider<ChannelsRepository>((ref) {
  return ChannelsRepository(ref.watch(dioClientProvider).dio);
});

class ChannelsNotifier extends AsyncNotifier<List<Channel>> {
  @override
  Future<List<Channel>> build() {
    return ref.read(channelsRepositoryProvider).fetchChannels();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(channelsRepositoryProvider).fetchChannels(),
    );
  }

  /// Optimistically flips `isSubscribed` locally, then confirms with the
  /// backend — reverting the local change if the request fails.
  Future<void> toggleSubscription(Channel channel) async {
    final current = state.value ?? [];
    final optimistic = current
        .map((c) => c.id == channel.id
            ? c.copyWith(isSubscribed: !c.isSubscribed)
            : c)
        .toList();
    state = AsyncData(optimistic);

    try {
      final repo = ref.read(channelsRepositoryProvider);
      final updated = channel.isSubscribed
          ? await repo.unsubscribe(channel.id)
          : await repo.subscribe(channel.id);
      final confirmed = (state.value ?? optimistic)
          .map((c) => c.id == updated.id ? updated : c)
          .toList();
      state = AsyncData(confirmed);
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }
}

final channelsNotifierProvider =
    AsyncNotifierProvider<ChannelsNotifier, List<Channel>>(ChannelsNotifier.new);

/// Channels the user is currently subscribed to — feeds the Feed screen's
/// empty state and the Create-Post channel picker.
final subscribedChannelsProvider = Provider<List<Channel>>((ref) {
  final channels = ref.watch(channelsNotifierProvider).value ?? [];
  return channels.where((c) => c.isSubscribed).toList();
});
