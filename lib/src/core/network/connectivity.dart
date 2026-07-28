import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

enum ConnectionStatus {
  online,

  /// The backend is unreachable — either there's no network at all, or there is
  /// one and the server isn't answering on it.
  offline,

  /// Transient: we just recovered. Held briefly so the banner can confirm the
  /// recovery before disappearing, then collapses to [online].
  backOnline,
}

extension ConnectionStatusX on ConnectionStatus {
  bool get isOffline => this == ConnectionStatus.offline;
}

/// How long the green "Back online" confirmation stays up before the banner hides.
const _backOnlineDuration = Duration(seconds: 2);

/// Backoff schedule for the health probe while we believe we're offline. Caps at
/// 30s so a long outage doesn't hammer the server, but stays snappy at the start
/// where a quick recovery (server restart, tunnel reconnect) is most likely.
const _probeBackoff = [
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
  Duration(seconds: 30),
];

/// Tracks whether the backend is reachable, from three independent signals.
///
/// No single signal is sufficient:
///  1. `connectivity_plus` reports *link* state. It catches airplane mode
///     instantly but happily says "connected to wifi" while the backend is down.
///  2. Real request outcomes, fed in by the Dio interceptor via [reportSuccess] /
///     [reportFailure]. This is the signal that catches a reachable network with
///     an unreachable server — the common case during a deploy or in local dev.
///  3. A backoff probe against `GET /health`, which is the only thing that can
///     notice recovery while the user is idle and issuing no requests.
class ConnectivityNotifier extends Notifier<ConnectionStatus> {
  Timer? _probeTimer;
  Timer? _backOnlineTimer;
  StreamSubscription<List<ConnectivityResult>>? _linkSubscription;
  int _probeAttempt = 0;

  /// A bare Dio with no interceptors: the probe must not attach an auth token,
  /// must not be re-entrantly reported back into this notifier, and needs a much
  /// shorter timeout than a real request so the backoff stays on schedule.
  late final Dio _probeDio = Dio(
    BaseOptions(
      baseUrl: '${AppConfig.apiBaseUrl}${AppConfig.apiPath}',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  @override
  ConnectionStatus build() {
    // Optimistic start: assume reachable until something says otherwise, so a
    // cold start doesn't flash a red banner before the first request completes.
    _linkSubscription = Connectivity().onConnectivityChanged.listen(
      _onLinkChanged,
    );
    ref.onDispose(() {
      _probeTimer?.cancel();
      _backOnlineTimer?.cancel();
      _linkSubscription?.cancel();
      _probeDio.close(force: true);
    });
    return ConnectionStatus.online;
  }

  void _onLinkChanged(List<ConnectivityResult> results) {
    final hasLink =
        results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none);
    if (!hasLink) {
      reportFailure();
      return;
    }
    // A link came back, but that says nothing about the server. Probe now rather
    // than declaring victory — and rather than waiting out the current backoff.
    if (state.isOffline) {
      _probeAttempt = 0;
      _scheduleProbe(immediate: true);
    }
  }

  /// Called by the Dio interceptor when any request succeeds.
  void reportSuccess() {
    if (!state.isOffline) return;
    _probeTimer?.cancel();
    _probeAttempt = 0;
    state = ConnectionStatus.backOnline;
    _backOnlineTimer?.cancel();
    _backOnlineTimer = Timer(_backOnlineDuration, () {
      if (state == ConnectionStatus.backOnline) state = ConnectionStatus.online;
    });
  }

  /// Called by the Dio interceptor on a connection-class failure.
  void reportFailure() {
    _backOnlineTimer?.cancel();
    if (state.isOffline) return;
    state = ConnectionStatus.offline;
    _probeAttempt = 0;
    _scheduleProbe();
  }

  void _scheduleProbe({bool immediate = false}) {
    _probeTimer?.cancel();
    final delay = immediate
        ? Duration.zero
        : _probeBackoff[_probeAttempt.clamp(0, _probeBackoff.length - 1)];
    _probeTimer = Timer(delay, _probe);
  }

  Future<void> _probe() async {
    if (!state.isOffline) return;
    try {
      await _probeDio.get<Map<String, dynamic>>('/health');
      reportSuccess();
    } catch (_) {
      _probeAttempt++;
      _scheduleProbe();
    }
  }
}

final connectivityProvider =
    NotifierProvider<ConnectivityNotifier, ConnectionStatus>(
      ConnectivityNotifier.new,
    );
