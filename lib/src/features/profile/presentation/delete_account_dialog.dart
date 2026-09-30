import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/errors/error_messages.dart';
import '../../auth/application/auth_providers.dart';
import '../application/profile_providers.dart';
import '../data/user_profile.dart';

/// Settings → Account → Delete account, in two slides.
///
/// The split is the point. The first slide is a *choice* nobody should make by
/// accident and nobody can make later — whether the posts go with the account —
/// and it is stated in terms of what other people lose, not in terms of database
/// rows. The second is the confirmation, and it is where the account is proved
/// rather than merely asserted.
///
/// Deliberately one dialog rather than two: a chain of `showDialog`s cannot go
/// back, and "wait, which did I pick?" is exactly the doubt this flow has to be
/// able to answer. Back on slide two returns to the choice with it still made.
///
/// Ends by signing out through [AuthNotifier.logout], not by pushing a route:
/// the account is gone, so what has to happen is what happens at every session
/// boundary — the token cleared, the cache wiped, the router falling back to the
/// login screen on its own.
Future<void> showDeleteAccountDialog(
  BuildContext context,
  UserProfile profile,
) {
  return showDialog<void>(
    context: context,
    // The one dialog in the app that must not be dismissable by tapping outside:
    // a half-finished deletion is fine to abandon, but the password field on the
    // second slide makes an accidental barrier tap feel like something happened.
    barrierDismissible: false,
    builder: (_) => _DeleteAccountDialog(profile: profile),
  );
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  /// Which slide is showing. Two is the whole flow; an enum would outweigh it.
  bool _confirming = false;

  /// Defaults to keeping the posts — the *less* destructive of two irreversible
  /// options, so a reader who stops reading and taps through does less harm.
  bool _deletePosts = false;

  final _passwordController = TextEditingController();
  var _obscurePassword = true;
  var _submitting = false;

  /// Server-side refusal, rendered under the password field rather than in a
  /// snackbar: a wrong password is about the field the user is looking at, and a
  /// snackbar over a dialog is easy to miss entirely.
  String? _passwordError;

  bool get _needsPassword => !widget.profile.isGoogleAccount;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (_needsPassword && _passwordController.text.isEmpty) {
      setState(() => _passwordError = l10n.validationPasswordRequired);
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _submitting = true;
      _passwordError = null;
    });
    try {
      await ref
          .read(profileRepositoryProvider)
          .deleteAccount(
            deletePosts: _deletePosts,
            currentPassword: _needsPassword ? _passwordController.text : null,
          );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _passwordError = messageFor(l10n, error);
      });
      return;
    }
    // Close first: `logout` sends the router to the login screen, and a dialog
    // still on the stack would sit over it.
    navigator.pop();
    await ref.read(authNotifierProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(
        _confirming
            ? l10n.deleteAccountConfirmTitle
            : l10n.deleteAccountChoiceTitle,
        style: _confirming
            ? theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.error,
              )
            : null,
      ),
      content: SingleChildScrollView(
        // Sized by whichever slide is showing, animated so the dialog grows into
        // the second one instead of snapping.
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _confirming
              ? _buildConfirmSlide(l10n)
              : _buildChoiceSlide(l10n),
        ),
      ),
      actions: _confirming
          ? [
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() => _confirming = false),
                child: Text(l10n.commonBack),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.deleteAccountConfirmAction),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => setState(() => _confirming = true),
                child: Text(l10n.commonContinue),
              ),
            ],
    );
  }

  Widget _buildChoiceSlide(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('choice'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.deleteAccountChoiceIntro, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        _ChoiceOption(
          selected: !_deletePosts,
          title: l10n.deleteAccountKeepPostsTitle,
          body: l10n.deleteAccountKeepPostsBody,
          onTap: () => setState(() => _deletePosts = false),
        ),
        const SizedBox(height: 8),
        _ChoiceOption(
          selected: _deletePosts,
          title: l10n.deleteAccountDeletePostsTitle,
          body: l10n.deleteAccountDeletePostsBody,
          onTap: () => setState(() => _deletePosts = true),
        ),
      ],
    );
  }

  Widget _buildConfirmSlide(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('confirm'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.deleteAccountConfirmBody, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        // Repeats the choice rather than trusting the user to remember which of
        // two similar-sounding options they picked one tap ago.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _deletePosts
                ? l10n.deleteAccountSummaryWithPosts
                : l10n.deleteAccountSummaryKeepingPosts,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ),
        if (_needsPassword) ...[
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
              labelText: l10n.deleteAccountPasswordLabel,
              errorText: _passwordError,
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
        ] else if (_passwordError != null) ...[
          // A Google account has no field to hang a failure under, so the one
          // place left is here.
          const SizedBox(height: 12),
          Text(
            _passwordError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// One of the two outcomes on the first slide.
///
/// A tappable card rather than a `RadioListTile`: each option needs a sentence
/// of consequence under it, and a radio tile's `subtitle` puts that in the same
/// visual weight as a setting's hint — too quiet for "other people stop being
/// able to read your posts".
class _ChoiceOption extends StatelessWidget {
  const _ChoiceOption({
    required this.selected,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
