import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/app_config/application/app_config_providers.dart';
import '../../../core/errors/error_messages.dart';
import '../application/auth_providers.dart';

/// Two steps in one screen, reached from the login screen's "Forgot
/// password?" link: enter the account's email, then enter the code that was
/// mailed to it alongside a new password.
///
/// The request step never tells the caller whether the email actually
/// belongs to an account — see `backend/app/api/password_reset.py` — so this
/// always moves on to the code step and shows the same "if an account
/// exists…" message, success or not. There is also no server-told resend
/// cooldown to count down (unlike email verification): the backend's abuse
/// control here is a plain rate limit, which surfaces through the ordinary
/// `rate_limited` error if it's ever hit.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

enum _Step { email, resetCode }

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  var _step = _Step.email;
  var _isSubmitting = false;
  var _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .forgotPassword(email: _emailController.text.trim());
      if (!mounted) return;
      setState(() => _step = _Step.resetCode);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.forgotPasswordRequestSentSnackbar)),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(messageFor(l10n, error))));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _resendCode() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    try {
      await ref
          .read(authRepositoryProvider)
          .forgotPassword(email: _emailController.text.trim());
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.forgotPasswordRequestSentSnackbar)),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(messageFor(l10n, error))));
    }
  }

  Future<void> _submitReset() async {
    if (!_resetFormKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .resetPassword(
            email: _emailController.text.trim(),
            code: _codeController.text.trim(),
            newPassword: _newPasswordController.text,
          );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.forgotPasswordResetSuccessSnackbar)),
      );
      context.go('/login');
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(messageFor(l10n, error))));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.forgotPasswordTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _step == _Step.email ? _emailStep(l10n) : _resetStep(l10n),
        ),
      ),
    );
  }

  Widget _emailStep(AppLocalizations l10n) {
    return Form(
      key: _emailFormKey,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.forgotPasswordEmailInstructions),
            const SizedBox(height: 24),
            TextFormField(
              controller: _emailController,
              decoration: InputDecoration(labelText: l10n.commonEmail),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onFieldSubmitted: (_) => _isSubmitting ? null : _submitEmail(),
              validator: (v) => (v == null || v.isEmpty)
                  ? l10n.validationEmailRequired
                  : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSubmitting ? null : _submitEmail,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.forgotPasswordSendCode),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resetStep(AppLocalizations l10n) {
    final appConfig = ref.watch(appConfigProvider).value;
    final requireStrongPassword = appConfig?.requireStrongPassword ?? false;
    final passwordMinLength = appConfig?.passwordMinLength ?? 1;

    return Form(
      key: _resetFormKey,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.forgotPasswordCodeInstructions(_emailController.text.trim()),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _codeController,
              decoration: InputDecoration(
                labelText: l10n.forgotPasswordCodeLabel,
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 4),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? l10n.forgotPasswordEnterCode
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _newPasswordController,
              decoration: InputDecoration(
                labelText: l10n.forgotPasswordNewPasswordLabel,
                suffixIcon: _obscureToggle(l10n),
              ),
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return l10n.validationPasswordRequired;
                }
                if (requireStrongPassword && v.length < passwordMinLength) {
                  return l10n.validationPasswordMinLength(passwordMinLength);
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmPasswordController,
              decoration: InputDecoration(
                labelText: l10n.forgotPasswordConfirmPasswordLabel,
                suffixIcon: _obscureToggle(l10n),
              ),
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              onFieldSubmitted: (_) => _isSubmitting ? null : _submitReset(),
              validator: (v) => v != _newPasswordController.text
                  ? l10n.validationPasswordsDoNotMatch
                  : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSubmitting ? null : _submitReset,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.forgotPasswordResetButton),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _isSubmitting ? null : _resendCode,
              child: Text(l10n.forgotPasswordResendCode),
            ),
            TextButton(
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() => _step = _Step.email),
              child: Text(l10n.forgotPasswordStartOver),
            ),
          ],
        ),
      ),
    );
  }

  Widget _obscureToggle(AppLocalizations l10n) {
    return IconButton(
      icon: Icon(
        _obscurePassword
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
      ),
      tooltip: _obscurePassword ? l10n.authShowPassword : l10n.authHidePassword,
      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
    );
  }
}
