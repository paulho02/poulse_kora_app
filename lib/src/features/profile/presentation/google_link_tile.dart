import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/app_config/application/app_config_providers.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../auth/application/auth_providers.dart';
import '../application/profile_providers.dart';
import '../data/user_profile.dart';
import 'link_google_dialog.dart';

/// Settings → Account row for Google sign-in.
///
/// Two states, both terminal in their own way: a Google account shows a static
/// "connected" row (nothing can unlink it — the upgrade is one-way), and a
/// password account gets a tappable row that performs the same irreversible
/// upgrade the login screen offers, behind the same warning plus the current
/// password (see [showLinkGoogleDialog]).
///
/// Renders nothing unless both the build and the backend have the feature on.
class GoogleLinkTile extends ConsumerStatefulWidget {
  const GoogleLinkTile({super.key, required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<GoogleLinkTile> createState() => _GoogleLinkTileState();
}

class _GoogleLinkTileState extends ConsumerState<GoogleLinkTile> {
  var _busy = false;

  Future<void> _link() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final service = ref.read(googleSignInServiceProvider);
      await service.ensureInitialized();
      if (!service.supportsDirectSignIn) {
        // Web needs Google's own rendered button to start a sign-in, which a
        // ListTile is not. Rather than smuggle one in here, say so: the user
        // can link from the login screen in the app instead. Checked before
        // the dialog, so nobody types a password for nothing.
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(l10n.settingsConnectGoogleUnsupported)),
            );
        }
        return;
      }
      if (!mounted) return;
      final linked = await showLinkGoogleDialog(
        context,
        widget.profile,
        obtainIdToken: service.signIn,
      );
      if (!linked) return;
      // The account type just changed, so re-read it: this row and the
      // change-password row above both key off `authProvider`.
      await ref.read(profileProvider.notifier).refresh();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabledOnServer =
        ref.watch(appConfigProvider).value?.googleOauthEnabled ?? false;
    final configured = ref.watch(googleSignInServiceProvider).isConfigured;
    if (!enabledOnServer || !configured) return const SizedBox.shrink();

    if (widget.profile.isGoogleAccount) {
      final googleEmail = widget.profile.googleEmail;
      return ListTile(
        leading: const Icon(Icons.verified_user_outlined),
        title: Text(l10n.settingsGoogleConnected),
        // Naming the account matters most when it differs from the contact
        // address above — otherwise the Email row and this one would silently
        // disagree with no explanation. Falls back to the generic line if the
        // backend didn't report one.
        subtitle: Text(
          googleEmail == null
              ? l10n.settingsGoogleConnectedSubtitle
              : l10n.settingsGoogleConnectedAs(googleEmail),
        ),
        enabled: false,
      );
    }

    return ListTile(
      leading: const Icon(Icons.link),
      title: Text(l10n.settingsConnectGoogle),
      subtitle: Text(l10n.settingsConnectGoogleSubtitle),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _busy ? null : () => unawaited(_link()),
    );
  }
}
