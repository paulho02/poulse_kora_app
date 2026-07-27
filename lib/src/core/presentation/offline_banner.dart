import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/connectivity.dart';

/// A thin status strip that appears when the backend is unreachable and briefly
/// confirms recovery.
///
/// Mounted in `MaterialApp.router`'s `builder` rather than in `AppShell`, so it
/// also covers login and register — the screens where a connection failure is
/// most confusing, since there's no cached content to fall back on there.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectivityProvider);

    return Column(
      children: [
        // AnimatedSize collapses to zero height when online, so the banner takes
        // no layout space at all rather than reserving a gap.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: status == ConnectionStatus.online
              ? const SizedBox(width: double.infinity)
              : _Bar(status: status),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final isOffline = status.isOffline;
    // Fixed, semantic colors rather than scheme colors: this must read as a
    // warning identically in light and dark themes.
    final background = isOffline
        ? const Color(0xFFC62828) // red 800
        : const Color(0xFF2E7D32); // green 800

    return Material(
      color: background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isOffline)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              else
                const Icon(Icons.check_circle_outline,
                    size: 14, color: Colors.white),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  isOffline
                      // Names the state and the fact that recovery is automatic,
                      // so there's no implied "go fix something" for the user.
                      ? "You're offline — reconnecting…"
                      : 'Back online',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
