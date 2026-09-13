import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../app_config/application/app_config_providers.dart';
import 'language_detector.dart';

/// The languages a **post** may be written in, as the backend currently
/// accepts them.
///
/// Read from `GET /config` rather than hardcoded, so the picker, the detector's
/// candidate set and the values `POST /posts` will accept can never disagree —
/// adding a language is then a backend setting plus a stopword list, not an app
/// release. Falls back to the pair this app ships copy for while the config
/// fetch is in flight or has failed, which is what `PublicAppConfig` defaults
/// to anyway.
///
/// **Not** `supportedAppLocales` (`core/settings/locale_settings.dart`). That
/// is the language this app's own interface is drawn in; this is the language
/// of the content flowing through it. They are separate settings on the backend
/// too (`SUPPORTED_LOCALES` vs `CONTENT_LANGUAGES`) and are free to diverge.
final contentLanguagesProvider = Provider<List<String>>((ref) {
  final config = ref.watch(appConfigProvider).value;
  return config?.contentLanguages ?? const ['en', 'de'];
});

/// The reserved "this post has no language" value. Server-supplied for the same
/// reason as [contentLanguagesProvider].
final languageUnspecifiedProvider = Provider<String>((ref) {
  return ref.watch(appConfigProvider).value?.languageUnspecified ?? 'und';
});

/// The on-device detector the composer uses to prefill its language picker.
///
/// Scoped to whatever the server accepts, so it can never suggest a language a
/// post could not actually be published in. Swap the implementation here — and
/// only here — to move to an ML model later; see `language_detector.dart`.
final languageDetectorProvider = Provider<LanguageDetector>((ref) {
  return StopwordLanguageDetector(
    candidates: ref.watch(contentLanguagesProvider),
  );
});

/// The name of a content language, in the reader's own interface language.
///
/// Deliberately not `Locale.fromSubtags(...).toLanguageTag()` or a bare code:
/// "EN" is jargon on a picker aimed at everyone, and a language's *endonym*
/// ("Deutsch") would be unreadable to someone who does not speak it — which is
/// exactly the person choosing what not to be shown.
String contentLanguageLabel(AppLocalizations l10n, String code) {
  switch (code) {
    case 'en':
      return l10n.contentLanguageEnglish;
    case 'de':
      return l10n.contentLanguageGerman;
    default:
      // A language the backend has and this app has no copy for yet. Showing
      // the raw code is ugly but honest, and it keeps the option selectable
      // rather than hiding content behind a missing translation.
      return code.toUpperCase();
  }
}
