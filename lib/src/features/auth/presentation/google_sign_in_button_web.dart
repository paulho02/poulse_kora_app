import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// Web "continue with Google" button.
///
/// Google renders this one itself: on web `supportsAuthenticate()` is false and
/// `authenticate()` throws `UnimplementedError`, because Identity Services only
/// starts a sign-in from a button it drew. Consequences for callers, both handled
/// in the auth screens:
///
/// - [onPressed] is ignored. There is nothing to hook - the SDK owns the tap.
/// - The result does not come back from a `Future`; it arrives on
///   `GoogleSignInService.idTokens`, which the screens listen to.
///
/// [label] is ignored too: the button's text is Google's, in Google's own
/// wording and the browser's locale, and is not ours to set.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Centered and width-capped: the rendered button has its own intrinsic size
    // and would otherwise sit flush-left inside the screens' stretched Column.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: web.renderButton(
          configuration: web.GSIButtonConfiguration(
            theme: Theme.of(context).brightness == Brightness.dark
                ? web.GSIButtonTheme.filledBlack
                : web.GSIButtonTheme.outline,
            size: web.GSIButtonSize.large,
            shape: web.GSIButtonShape.rectangular,
            logoAlignment: web.GSIButtonLogoAlignment.left,
          ),
        ),
      ),
    );
  }
}
