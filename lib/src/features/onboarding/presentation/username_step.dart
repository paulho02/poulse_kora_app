import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../profile/application/profile_providers.dart';

/// Onboarding step shown to Google signups only: confirm the username.
///
/// Password registration asks for a username on the register form, but Google
/// supplies none, so the backend derives one from the Google display name (see
/// `app/core/username.py`). That guess is reasonable but it is still a guess,
/// and it is the name other people see — so this shows it pre-filled and
/// editable rather than assigning it silently.
class UsernameStep extends ConsumerStatefulWidget {
  const UsernameStep({
    super.key,
    required this.initialUsername,
    required this.onContinue,
  });

  final String initialUsername;
  final VoidCallback onContinue;

  static const minLength = 3;
  static const maxLength = 20;

  @override
  ConsumerState<UsernameStep> createState() => _UsernameStepState();
}

class _UsernameStepState extends ConsumerState<UsernameStep> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initialUsername);
  var _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final username = _controller.text.trim();

    // Unchanged means the derived name is already what the server has; skip the
    // round trip rather than PATCH the same value back.
    if (username == widget.initialUsername) {
      widget.onContinue();
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(profileProvider.notifier).updateUsername(username);
      if (mounted) widget.onContinue();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _validate(String? value, AppLocalizations l10n) {
    final username = value?.trim() ?? '';
    if (username.isEmpty) return l10n.validationUsernameRequired;
    if (username.length < UsernameStep.minLength) {
      return l10n.validationUsernameTooShort(UsernameStep.minLength);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.onboardingUsernameTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.onboardingUsernameSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: l10n.commonUsername,
                  counterText: '',
                ),
                maxLength: UsernameStep.maxLength,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                onFieldSubmitted: (_) => _submitting ? null : _submit(),
                validator: (v) => _validate(v, l10n),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.commonContinue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
