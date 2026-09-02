import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/app_config/application/app_config_providers.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/errors/error_messages.dart';
import '../../auth/application/auth_providers.dart';
import '../application/email_verification_providers.dart';

/// Shown after registration (or on a later login) while the account's
/// `is_verified` flag is still false and the backend has
/// `REQUIRE_EMAIL_VERIFICATION` on - see the `/verify-email` redirect in
/// `routing/app_router.dart`. Blocks nothing on its own; the router is what
/// keeps the user here until `profileProvider` reports verified.
///
/// Sends a code every time it opens (see [_sendInitialCode]) rather than
/// waiting for the user to hit "resend" - the account may have landed here
/// with no code ever sent at all, e.g. `REQUIRE_EMAIL_VERIFICATION` turned on
/// after this account registered.
class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  Timer? _cooldownTimer;
  int _cooldownSecondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    _sendInitialCode();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  /// Fires the moment this screen mounts, e.g. right after registration or on
  /// a login that lands here. Deliberately reuses the resend endpoint rather
  /// than a dedicated one - it already no-ops (`is_verified: true`) for an
  /// already-verified account and rate-limits via the same cooldown.
  ///
  /// The common path (registration, which already mailed a code and started
  /// the cooldown - see backend `UserManager.on_after_register`) hits
  /// `resend_cooldown` here every time; that's expected, not a failure, so it
  /// starts the countdown silently instead of alarming the user with an error
  /// they didn't cause. Any other failure (e.g. offline) is left silent too -
  /// the manual "resend" button is still there to retry.
  Future<void> _sendInitialCode() async {
    final defaultCooldown = ref
        .read(appConfigProvider)
        .value
        ?.emailVerificationResendCooldownSeconds;
    try {
      await ref.read(emailVerificationProvider.notifier).resend();
      if (!mounted) return;
      _startCooldown(defaultCooldown ?? 60);
    } catch (error) {
      if (!mounted) return;
      final relayError = asRelayException(error);
      if (relayError.error == 'resend_cooldown') {
        final retryAfter = relayError.detail['retry_after'];
        _startCooldown(
          retryAfter is int ? retryAfter : (defaultCooldown ?? 60),
        );
      }
    }
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSecondsRemaining = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldownSecondsRemaining -= 1;
        if (_cooldownSecondsRemaining <= 0) timer.cancel();
      });
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Otherwise a still-showing error from a previous failed attempt (the
    // default SnackBar duration is 4s) can outlive this one and linger into
    // whatever screen a *successful* retry navigates to.
    ScaffoldMessenger.of(context).clearSnackBars();
    await ref
        .read(emailVerificationProvider.notifier)
        .confirm(_codeController.text.trim());
  }

  Future<void> _resend() async {
    final defaultCooldown = ref
        .read(appConfigProvider)
        .value
        ?.emailVerificationResendCooldownSeconds;
    try {
      await ref.read(emailVerificationProvider.notifier).resend();
      if (!mounted) return;
      _startCooldown(defaultCooldown ?? 60);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).emailVerifyResendSnackbar),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final relayError = asRelayException(error);
      if (relayError.error == 'resend_cooldown') {
        final retryAfter = relayError.detail['retry_after'];
        if (retryAfter is int) _startCooldown(retryAfter);
      }
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(messageFor(l10n, error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(emailVerificationProvider);
    final isSubmitting = state.isLoading;
    final l10n = AppLocalizations.of(context);

    ref.listen(emailVerificationProvider, (previous, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(l10n, next.error))));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.emailVerifyTitle),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: isSubmitting
                ? null
                : () => ref.read(authNotifierProvider.notifier).logout(),
            child: Text(l10n.commonLogOut),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.emailVerifyInstructions, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _codeController,
                  decoration: InputDecoration(
                    labelText: l10n.emailVerifyCodeLabel,
                  ),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 4),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.emailVerifyEnterCode
                      : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: isSubmitting ? null : _submit,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.emailVerifyButton),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: (isSubmitting || _cooldownSecondsRemaining > 0)
                      ? null
                      : _resend,
                  child: Text(
                    _cooldownSecondsRemaining > 0
                        ? l10n.emailVerifyResendIn(_cooldownSecondsRemaining)
                        : l10n.emailVerifyResendPrompt,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
