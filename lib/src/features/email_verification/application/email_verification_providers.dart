import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../profile/application/profile_providers.dart';
import '../data/email_verification_repository.dart';

final emailVerificationRepositoryProvider =
    Provider<EmailVerificationRepository>(
      (ref) => EmailVerificationRepository(ref.watch(dioClientProvider).dio),
    );

/// Mirrors `AuthNotifier`'s shape: state is whether the account is now
/// verified, so a successful `confirm` flips it to `true` and the screen (or
/// the router) can react. Never fetches on its own - there is no "verification
/// status" endpoint separate from the profile, so this starts at `false` and
/// only ever moves forward from an explicit confirm.
class EmailVerificationNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async => false;

  Future<void> confirm(String code) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final verified = await ref
          .read(emailVerificationRepositoryProvider)
          .confirm(code);
      if (verified) {
        // The router's redirect reads `profileProvider`'s `isVerified`, not
        // this notifier's state - refresh it so the redirect actually fires.
        await ref.read(profileProvider.notifier).refresh();
      }
      return verified;
    });
  }

  /// Resending doesn't change verified status, so this deliberately leaves
  /// `state` alone on success - only failures (e.g. `resend_cooldown`) need to
  /// reach the screen, which it does by rethrowing.
  Future<void> resend() async {
    await ref.read(emailVerificationRepositoryProvider).resend();
  }
}

final emailVerificationProvider =
    AsyncNotifierProvider<EmailVerificationNotifier, bool>(
      EmailVerificationNotifier.new,
    );
