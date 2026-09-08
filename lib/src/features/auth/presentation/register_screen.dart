import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/app_config/application/app_config_providers.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/presentation/field_info_icon.dart';
import '../../../core/presentation/language_picker.dart';
import '../application/auth_providers.dart';
import 'google_auth_section.dart';
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

  /// The username the server has already refused as taken, if any.
  ///
  /// Kept so the refusal lands *under the field* rather than only in a snackbar
  /// that scrolls away — and so a second tap on "create account" with the same
  /// name is stopped here instead of spending another round trip on an answer
  /// we already have. Cleared as soon as the text changes.
  String? _takenUsername;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Still the username the server just refused (it is cleared on the first
    // keystroke), so the answer is already known - don't spend a round trip
    // asking again.
    if (_takenUsername != null) return;
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
        // A taken username is the one failure that points at a specific field,
        // so it is shown there instead of in a snackbar — the fields are still
        // filled in and the fix is to edit one of them.
        if (asRelayException(next.error).error == 'username_taken') {
          setState(() => _takenUsername = _usernameController.text.trim());
          return;
        }
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
                    decoration: InputDecoration(
                      labelText: l10n.commonUsername,
                      // Said here rather than as a `helperText` line: this is
                      // the one field on the form whose value other people see,
                      // and it is worth saying before someone types their real
                      // name into it.
                      suffixIcon: FieldInfoIcon(
                        message: l10n.usernameVisibleToOthers,
                      ),
                      // Not a `validator` rule: the form only re-validates on
                      // submit, so a validator-based version of this would keep
                      // the message on screen while the user types the new name.
                      errorText: _takenUsername == null
                          ? null
                          : l10n.errorUsernameTaken,
                    ),
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newUsername],
                    onChanged: (_) {
                      if (_takenUsername != null) {
                        setState(() => _takenUsername = null);
                      }
                    },
                    validator: (v) => (v == null || v.trim().isEmpty)
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
                  // Same endpoint as on the login screen: signing up and
                  // signing in with Google are one flow, and which of the two
                  // it turns out to be depends only on whether the address is
                  // already known.
                  GoogleAuthSection(label: l10n.authSignUpWithGoogle),
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
