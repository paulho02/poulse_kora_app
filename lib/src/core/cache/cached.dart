/// A value plus where it came from, so a screen can render content *and* be
/// honest about whether it's live.
///
/// Showing stale data silently is the failure mode this exists to prevent: a
/// user acting on a 40-minute-old feed with no indication is worse UX than an
/// error, because they only find out when the action fails.
class Cached<T> {
  const Cached({
    required this.data,
    required this.fetchedAt,
    required this.isStale,
  });

  /// Fresh from the network, just now.
  Cached.live(this.data)
      : fetchedAt = DateTime.now(),
        isStale = false;

  /// Read back from disk after the network was unreachable.
  const Cached.stale(this.data, this.fetchedAt) : isStale = true;

  final T data;
  final DateTime fetchedAt;
  final bool isStale;

  Cached<R> map<R>(R Function(T) transform) => Cached(
        data: transform(data),
        fetchedAt: fetchedAt,
        isStale: isStale,
      );

  /// Human-readable age, e.g. "Saved copy from 12 minutes ago". `null` when live.
  String? get staleLabel {
    if (!isStale) return null;
    final age = DateTime.now().difference(fetchedAt);
    if (age.inMinutes < 1) return 'Saved copy from just now';
    if (age.inMinutes < 60) {
      final m = age.inMinutes;
      return 'Saved copy from $m ${m == 1 ? 'minute' : 'minutes'} ago';
    }
    if (age.inHours < 24) {
      final h = age.inHours;
      return 'Saved copy from $h ${h == 1 ? 'hour' : 'hours'} ago';
    }
    final d = age.inDays;
    return 'Saved copy from $d ${d == 1 ? 'day' : 'days'} ago';
  }
}
