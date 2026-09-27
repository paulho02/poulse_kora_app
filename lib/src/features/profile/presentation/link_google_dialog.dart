import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/errors/error_messages.dart';
import '../../auth/application/auth_providers.dart';
import '../data/user_profile.dart';

/// Settings → Account → Connect Google: the warning, the password, the link.
///
/// The password is asked for because the backend requires it
/// (`POST /auth/google/link`): linking destroys the password, so a stolen token
/// alone must not be able to bind somebody else's Google account and lock the
/// owner out. Asked *before* the Google picker, since the picker is the part
/// that takes the user out of the app.
///
/// The whole flow runs from inside the dialog rather than after it closes, so
/// a wrong password lands under the field it is about — the same reasoning as
/// the delete-account dialog — instead of in a snackbar after a trip through
/// Google's account picker.
///
/// [obtainIdToken] is the Google sign-in, injected so tests need no plugin.
/// It returns null when the picker is dismissed, which leaves the dialog open.
///
/// Resolves to true once the account is linked.
Future<bool> showLinkGoogleDialog(
  BuildContext context,
  UserProfile profile, {
  required Future<String?> Function() obtainIdToken,
}) async {
  final linked = await showDialog<bool>(
    context: context,
    // As in the delete-account dialog: a typed password makes an accidental
    // barrier tap feel like something happened.
    barrierDismissible: false,
    builder: (_) =>
        _LinkGoogleDialog(profile: profile, obtainIdToken: obtainIdToken),
  );
  return linked ?? false;
}

class _LinkGoogleDialog extends ConsumerStatefulWidget {
  const _LinkGoogleDialog({required this.profile, required this.obtainIdToken});

  final UserProfile profile;
  final Future<String?> Function() obtainIdToken;

  @override
  ConsumerState<_LinkGoogleDialog> createState() => _LinkGoogleDialogState();
}

class _LinkGoogleDialogState extends ConsumerState<_LinkGoogleDialog> {
  final _passwordController = TextEditingController();
  var _obscurePassword = true;
  var _submitting = false;
  String? _passwordError;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _passwordError = l10n.validationPasswordRequired);
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _submitting = true;
      _passwordError = null;
    });
    try {
      final idToken = await widget.obtainIdToken();
      if (idToken == null) {
        // Picker dismissed — not an error; the password is still typed in.
        if (mounted) setState(() => _submitting = false);
        return;
      }
      await ref
          .read(authRepositoryProvider)
          .linkGoogle(idToken: idToken, currentPassword: password);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _passwordError = messageFor(l10n, error);
      });
      return;
    }
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.authLinkGoogleTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Not the login screen's copy: there the Google address *is* the
            // account address (that is how the two were matched), while here
            // they may well differ and the account keeps its own.
            Text(
              l10n.authLinkGoogleSettingsBody(widget.profile.email),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              autofocus: true,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !_submitting,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submitting ? null : _submit(),
              onChanged: (_) {
                if (_passwordError != null) {
                  setState(() => _passwordError = null);
                }
              },
              decoration: InputDecoration(
                labelText: l10n.authLinkGooglePasswordLabel,
                // Errors other than the password's own (a Google account
                // already in use, a failed sign-in) land here too: the dialog
                // has no other place for them and they still need correcting
                // from here.
                errorText: _passwordError,
                errorMaxLines: 3,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  tooltip: _obscurePassword
                      ? l10n.authShowPassword
                      : l10n.authHidePassword,
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.authLinkGoogleConfirm),
        ),
      ],
    );
  }
}
