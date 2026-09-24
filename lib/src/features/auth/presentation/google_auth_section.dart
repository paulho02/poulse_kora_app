import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/app_config/application/app_config_providers.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/presentation/error_state_view.dart';
import '../application/auth_providers.dart';
import 'google_sign_in_button.dart';

/// The "or continue with Google" block shared by the login and register screens.
///
/// Owns the whole Google flow, including the upgrade handshake: the backend
/// answers 409 `google_link_required` when the Google address already belongs to
/// a password account, and this asks the user to confirm before re-sending the
/// same ID token with `link_existing`. The confirmation lives here rather than in
/// `AuthNotifier` because that 409 is a question, not a failure - see
/// `completeGoogleSignIn`.
///
/// Renders nothing at all unless both the build (a client ID) and the backend
/// (`google_oauth_enabled`) have the feature on, so it is safe to place
/// unconditionally.
class GoogleAuthSection extends ConsumerStatefulWidget {
  const GoogleAuthSection({super.key, required this.label});

  /// "Continue with Google" / "Sign up with Google". Ignored on web, where the
  /// button is Google's own and words itself.
  final String label;

  @override
  ConsumerState<GoogleAuthSection> createState() => _GoogleAuthSectionState();
}

class _GoogleAuthSectionState extends ConsumerState<GoogleAuthSection> {
  StreamSubscription<String>? _webTokens;
  var _initialized = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final service = ref.read(googleSignInServiceProvider);
    if (!service.isConfigured) return;
    try {
      await service.ensureInitialized();
    } catch (_) {
      // A misconfigured client ID must not take the login screen down with it —
      // leave the section hidden and let password sign-in carry on working.
      return;
    }
    if (!mounted) return;
    if (!service.supportsDirectSignIn) {
      // Web: the flow starts inside Google's own button, so the resulting token
      // arrives on this stream instead of from a call we made.
      _webTokens = service.idTokens.listen(_handleIdToken);
    }
    setState(() => _initialized = true);
  }

  @override
  void dispose() {
    _webTokens?.cancel();
    super.dispose();
  }

  Future<void> _startNativeSignIn() async {
    setState(() => _busy = true);
    String? idToken;
    try {
      idToken = await ref.read(googleSignInServiceProvider).signIn();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // Null means the user backed out of the account picker. Not an error, and
    // showing one for it would be actively confusing.
    if (idToken == null) return;
    await _handleIdToken(idToken);
  }

  Future<void> _handleIdToken(String idToken) async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      String accessToken;
      try {
        accessToken = await ref
            .read(authRepositoryProvider)
            .loginWithGoogle(idToken: idToken);
      } on Object catch (error) {
        final failure = asPeerkolaException(error);
        if (failure.error != 'google_link_required') rethrow;
        if (!mounted) return;
        final email = failure.detail['email'] as String? ?? '';
        if (!await _confirmUpgrade(email)) return;
        // Same ID token: Google's are valid for about an hour, so it easily
        // outlives a dialog, and the backend keeps no state between the two
        // calls.
        accessToken = await ref
            .read(authRepositoryProvider)
            .loginWithGoogle(idToken: idToken, linkExisting: true);
      }
      await ref
          .read(authNotifierProvider.notifier)
          .completeGoogleSignIn(accessToken);
      // No navigation here: the router's redirect watches `authNotifierProvider`
      // and takes over once it flips to signed-in.
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The irreversibility warning. Returns false if the dialog is dismissed by
  /// any means, so a stray tap outside it can never trigger the upgrade.
  Future<bool> _confirmUpgrade(String email) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.authLinkGoogleTitle),
        content: Text(l10n.authLinkGoogleBody(email)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.authLinkGoogleConfirm),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final enabledOnServer =
        ref.watch(appConfigProvider).value?.googleOauthEnabled ?? false;
    if (!_initialized || !enabledOnServer) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                l10n.authOrDivider,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 20),
        if (_busy)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          GoogleSignInButton(
            label: widget.label,
            onPressed: _startNativeSignIn,
          ),
      ],
    );
  }
}
