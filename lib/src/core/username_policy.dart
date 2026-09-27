import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';

/// What a username may be: lowercase ASCII letters, digits and `_`, between
/// [minLength] and [maxLength] characters.
///
/// Mirrors the backend's `app/core/username_policy.py`, which is the authority
/// (it answers `username_invalid` / `username_taken`). The rule exists because
/// the name is shown on every post: with one case and one script, nobody can
/// register a lookalike of somebody else's name.
///
/// Both username fields (register, onboarding) share this, so the two cannot
/// drift apart. Typing is shaped rather than refused: capitals are lowercased
/// as they are typed and anything else simply doesn't appear — the helper line
/// under the field says why.
abstract final class UsernamePolicy {
  static const minLength = 3;
  static const maxLength = 30;

  static final _valid = RegExp(r'^[a-z0-9_]+$');

  static final List<TextInputFormatter> inputFormatters = [
    const _AsciiLowercaseFormatter(),
    FilteringTextInputFormatter.allow(RegExp('[a-z0-9_]')),
  ];

  static String? validate(String? value, AppLocalizations l10n) {
    final username = value?.trim() ?? '';
    if (username.isEmpty) return l10n.validationUsernameRequired;
    if (username.length < minLength) {
      return l10n.validationUsernameTooShort(minLength);
    }
    // Unreachable through the formatters; kept for text set programmatically.
    if (!_valid.hasMatch(username)) return l10n.usernameRules;
    return null;
  }
}

/// Lowercases A–Z only. A full `toLowerCase()` can change the string's length
/// (`İ` becomes two code units), which would leave the selection pointing past
/// the text; anything non-ASCII is dropped by the next formatter anyway.
class _AsciiLowercaseFormatter extends TextInputFormatter {
  const _AsciiLowercaseFormatter();

  static final _upper = RegExp('[A-Z]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!_upper.hasMatch(newValue.text)) return newValue;
    return newValue.copyWith(
      text: newValue.text.replaceAllMapped(_upper, (m) => m[0]!.toLowerCase()),
    );
  }
}
