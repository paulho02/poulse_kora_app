import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/core/errors/api_exception.dart';
import 'src/core/providers.dart';
import 'src/core/settings/app_settings.dart';
import 'src/features/auth/application/auth_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Warmed here so every later read is synchronous. That's what lets the very
  // first frame paint in the user's saved theme instead of flashing the default
  // one while an async load resolves — and it works with no network at all.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      retry: _retryPolicy,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // Wired here, at the composition root, so `core/` doesn't have to know
        // the auth feature exists — and so the network client isn't reading the
        // auth state it is itself configured by.
        onUnauthorizedProvider.overrideWith(
          (ref) =>
              () => ref.read(authNotifierProvider.notifier).logout(),
        ),
      ],
      child: const PeerkolaApp(),
    ),
  );
}

/// Riverpod 3 retries a failed provider automatically (10 times, exponential
/// backoff) and keeps the state in `loading` while it does.
///
/// For a connectivity failure that is exactly wrong: offline with nothing cached,
/// a screen would spin for minutes and never reach its error state — the user
/// gets no banner explanation, no message and no retry button, just a spinner.
/// Recovery is already handled deliberately: `ConnectivityNotifier` probes
/// `/health` on a backoff, and reconnecting refreshes the providers that failed
/// (see `PeerkolaApp`). So stop retrying and let the error surface.
///
/// Non-connectivity errors keep a short bounded backoff, which covers a genuinely
/// transient blip without hiding a persistent failure.
Duration? _retryPolicy(int retryCount, Object error) {
  if (asPeerkolaException(error).isConnectivityFailure) return null;
  if (retryCount >= 2) return null;
  return Duration(milliseconds: 200 * (1 << retryCount));
}
