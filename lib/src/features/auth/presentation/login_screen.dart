import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/presentation/language_picker.dart';
import '../application/auth_providers.dart';
import 'google_auth_section.dart';
import 'server_settings_sheet.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _obscurePassword = true;

  @override
  void dispose() {
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
        .login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;
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
        title: Text(l10n.authLogIn),
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
                  Text(
                    'Relay',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 32),
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
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => isLoading ? null : _submit(),
                    validator: (v) => (v == null || v.isEmpty)
                        ? l10n.validationPasswordRequired
                        : null,
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
                        : Text(l10n.authLogIn),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: isLoading ? null : () => context.go('/register'),
                    child: Text(l10n.authGoToRegister),
                  ),
                  // Hides itself unless both this build and the backend have
                  // Google sign-in turned on, so no gating is needed here.
                  GoogleAuthSection(label: l10n.authContinueWithGoogle),
                  // Reachable without an account on purpose: "I can't sign
                  // in" and "registration won't take my email" are the reports
                  // that cannot be filed from anywhere inside the app, and the
                  // backend accepts this one unauthenticated for the same
                  // reason. Pushed, not `go`, so backing out returns here with
                  // whatever was typed still in the fields.
                  TextButton.icon(
                    onPressed: () => context.push('/feedback'),
                    icon: const Icon(Icons.feedback_outlined, size: 18),
                    label: Text(l10n.feedbackOpen),
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
