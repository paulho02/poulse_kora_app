import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../errors/api_exception.dart';
import '../errors/error_messages.dart';

/// The one full-screen failure state, shaped to match the empty states elsewhere
/// in the app so a failure looks designed rather than accidental.
///
/// Only reached when there is nothing cached to show — a screen that *can* fall
/// back to saved content should do that and let the offline banner explain the
/// staleness instead.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({super.key, required this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isOffline =
        error is PeerkolaApiException &&
        (error as PeerkolaApiException).isConnectivityFailure;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // Always scrollable so an enclosing RefreshIndicator still picks up the
        // pull gesture — retrying by pulling down is the reflex here.
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isOffline ? Icons.cloud_off_outlined : Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    titleFor(l10n, error),
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    messageFor(l10n, error),
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: onRetry,
                      child: Text(l10n.errorStateTryAgain),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The subtle "this is a saved copy" line shown above stale content.
class StaleDataNotice extends StatelessWidget {
  const StaleDataNotice({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a failure as a snackbar. Centralized so every error the user triggers
/// looks and reads the same, whether it came from the server or from being offline.
void showErrorSnackBar(BuildContext context, Object? error) {
  showErrorSnackBarOn(
    ScaffoldMessenger.of(context),
    AppLocalizations.of(context),
    error,
  );
}

/// Same, but against a messenger (and localizations) captured *before* the
/// failing await.
///
/// Necessary wherever the widget reporting the error may not survive long enough
/// to report it. An optimistic review unmounts the `PostCard` the instant it's
/// tapped, and the detail sheet pops itself — so by the time the request fails,
/// `context` is defunct and a `mounted` check silently swallows the message. Grab
/// the messenger (and `l10n`, for the same reason) while the widget is still
/// alive and the snackbar always lands.
void showErrorSnackBarOn(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  Object? error,
) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(messageFor(l10n, error)),
        behavior: SnackBarBehavior.floating,
      ),
    );
}
