import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/app_config/application/app_config_providers.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/presentation/language_picker.dart';
import '../application/auth_providers.dart';
import 'server_settings_sheet.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Otherwise a still-showing error from a previous failed attempt (the
    // default SnackBar duration is 4s) can outlive this one and linger into
    // whatever screen a *successful* retry navigates to.
    ScaffoldMessenger.of(context).clearSnackBars();
    await ref
        .read(authNotifierProvider.notifier)
        .register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          username: _usernameController.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;

    // The server is always the source of truth (a rejected password still
    // surfaces via `register_invalid_password`'s `reason`) - this only avoids
    // hassling the user with a client-side minimum the backend isn't actually
    // enforcing. Fails open (no client-side minimum) if the config hasn't
    // loaded yet, same bias as the rest of the app's config-driven UI.
    final appConfig = ref.watch(appConfigProvider).value;
    final requireStrongPassword = appConfig?.requireStrongPassword ?? false;
    final passwordMinLength = appConfig?.passwordMinLength ?? 1;
    final l10n = AppLocalizations.of(context);

    ref.listen(authNotifierProvider, (previous, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(l10n, next.error))));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.authCreateAccount),
        actions: const [LanguagePickerButton(), ServerSettingsButton()],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(labelText: l10n.commonUsername),
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newUsername],
                    validator: (v) => (v == null || v.isEmpty)
                        ? l10n.validationUsernameRequired
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(labelText: l10n.commonEmail),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) => (v == null || v.isEmpty)
                        ? l10n.validationEmailRequired
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: l10n.commonPassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        tooltip: _obscurePassword
                            ? l10n.authShowPassword
                            : l10n.authHidePassword,
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    // Password managers/keyboards must not learn or suggest
                    // this text — autocorrect can otherwise offer it back as
                    // a spelling "correction" on some Android keyboards.
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    // `.newPassword`, not `.password`: this is an account
                    // being created, so a password manager should offer to
                    // *generate* one rather than fill in an existing one.
                    autofillHints: const [AutofillHints.newPassword],
                    onFieldSubmitted: (_) => isLoading ? null : _submit(),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return l10n.validationPasswordRequired;
                      }
                      if (requireStrongPassword &&
                          v.length < passwordMinLength) {
                        return l10n.validationPasswordMinLength(
                          passwordMinLength,
                        );
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: isLoading ? null : _submit,
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.authCreateAccount),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: isLoading ? null : () => context.go('/login'),
                    child: Text(l10n.authGoToLogin),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
