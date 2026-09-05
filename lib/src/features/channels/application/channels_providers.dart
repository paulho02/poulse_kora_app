import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached.dart';
import '../../../core/providers.dart';
import '../data/channel.dart';
import '../data/channels_repository.dart';

final channelsRepositoryProvider = Provider<ChannelsRepository>((ref) {
  return ChannelsRepository(
    ref.watch(dioClientProvider).dio,
    ref.watch(jsonCacheProvider),
  );
});

class ChannelsNotifier extends AsyncNotifier<Cached<List<Channel>>> {
  @override
  Future<Cached<List<Channel>>> build() {
    return ref.read(channelsRepositoryProvider).fetchChannels();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(channelsRepositoryProvider).fetchChannels(),
    );
  }

  /// Re-fetch without blanking the list, for the price refresh that runs on a
  /// timer while channel prices are on screen (see `ChannelsScreen`).
  ///
  /// [refresh] is right for a pull-to-refresh, where an empty list under the
  /// spinner is what was asked for. Here it would replace a list someone is
  /// reading with a spinner once every price window, so this keeps the current
  /// data on screen until new data actually arrives — and keeps it if none
  /// does, since a background refresh that fails offline should cost nothing.
  Future<void> refreshPrices() async {
    final next = await AsyncValue.guard(
      () => ref.read(channelsRepositoryProvider).fetchChannels(),
    );
    if (next case AsyncData()) state = next;
  }

  /// Optimistically flips `isSubscribed` locally, then confirms with the
  /// backend — reverting the local change if the request fails (including when
  /// the failure is simply that we're offline).
  Future<void> toggleSubscription(Channel channel) async {
    final current = state.value;
    if (current == null) return;
    final optimistic = current.map(
      (channels) => channels
          .map(
            (c) => c.id == channel.id
                ? c.copyWith(isSubscribed: !c.isSubscribed)
                : c,
          )
          .toList(),
    );
    state = AsyncData(optimistic);

    try {
      final repo = ref.read(channelsRepositoryProvider);
      final updated = channel.isSubscribed
          ? await repo.unsubscribe(channel.id)
          : await repo.subscribe(channel.id);
      final confirmed = (state.value ?? optimistic).map(
        (channels) =>
            channels.map((c) => c.id == updated.id ? updated : c).toList(),
      );
      state = AsyncData(confirmed);
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }
}

final channelsNotifierProvider =
    AsyncNotifierProvider<ChannelsNotifier, Cached<List<Channel>>>(
      ChannelsNotifier.new,
    );

/// Channels the user is currently subscribed to — feeds the Feed screen's
/// empty state and the Create-Post channel picker.
final subscribedChannelsProvider = Provider<List<Channel>>((ref) {
  final channels = ref.watch(channelsNotifierProvider).value?.data ?? [];
  return channels.where((c) => c.isSubscribed).toList();
});
