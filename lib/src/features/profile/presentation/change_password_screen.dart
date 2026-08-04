import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/app_config/application/app_config_providers.dart';
import '../../../core/errors/error_messages.dart';
import '../../auth/application/auth_providers.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  var _obscurePassword = true;
  var _isSubmitting = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(
            currentPassword: _currentPasswordController.text,
            newPassword: _newPasswordController.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.changePasswordSuccess)),
      );
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
    // Same bias as the register screen: the server is always the source of
    // truth (a rejected new password still surfaces via
    // `change_password_invalid_password`'s `reason`), this is only a hint so
    // the user isn't hassled with a client-side minimum the backend isn't
    // actually enforcing. Fails open if the config hasn't loaded yet.
    final appConfig = ref.watch(appConfigProvider).value;
    final requireStrongPassword = appConfig?.requireStrongPassword ?? false;
    final passwordMinLength = appConfig?.passwordMinLength ?? 1;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.changePasswordTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _currentPasswordController,
                  decoration: InputDecoration(
                    labelText: l10n.changePasswordCurrentPasswordLabel,
                    suffixIcon: _obscureToggle(),
                  ),
                  obscureText: _obscurePassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.password],
                  validator: (v) => (v == null || v.isEmpty)
                      ? l10n.validationPasswordRequired
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _newPasswordController,
                  decoration: InputDecoration(
                    labelText: l10n.changePasswordNewPasswordLabel,
                    suffixIcon: _obscureToggle(),
                  ),
                  obscureText: _obscurePassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  // `.newPassword`, not `.password`: a manager should offer to
                  // *generate* one, same reasoning as the register screen.
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return l10n.validationPasswordRequired;
                    }
                    if (requireStrongPassword && v.length < passwordMinLength) {
                      return l10n.validationPasswordMinLength(
                        passwordMinLength,
                      );
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: l10n.changePasswordConfirmPasswordLabel,
                    suffixIcon: _obscureToggle(),
                  ),
                  obscureText: _obscurePassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onFieldSubmitted: (_) => _isSubmitting ? null : _submit(),
                  validator: (v) => v != _newPasswordController.text
                      ? l10n.validationPasswordsDoNotMatch
                      : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.changePasswordSubmit),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _obscureToggle() {
    final l10n = AppLocalizations.of(context);
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
