/// Backend feature flags the client needs before it can know how to behave
/// (see backend `GET /config`, `app.schemas.app_config.PublicAppConfig`). The
/// server stays the source of truth either way; this only tells the client
/// which UI path to take.
class PublicAppConfig {
  const PublicAppConfig({
    required this.requireEmailVerification,
    required this.requireStrongPassword,
    required this.passwordMinLength,
    required this.passwordMinCharacterClasses,
    required this.emailVerificationResendCooldownSeconds,
    required this.googleOauthEnabled,
    required this.contentLanguages,
    required this.languageUnspecified,
  });

  factory PublicAppConfig.fromJson(
    Map<String, dynamic> json,
  ) => PublicAppConfig(
    requireEmailVerification: json['require_email_verification'] as bool,
    requireStrongPassword: json['require_strong_password'] as bool,
    passwordMinLength: json['password_min_length'] as int,
    passwordMinCharacterClasses: json['password_min_character_classes'] as int,
    emailVerificationResendCooldownSeconds:
        json['email_verification_resend_cooldown_seconds'] as int,
    // Defaulted rather than a hard cast, unlike its siblings: a backend that
    // predates this flag simply omits it, and that must read as "off" rather
    // than throw and take the whole config down with it.
    googleOauthEnabled: json['google_oauth_enabled'] as bool? ?? false,
    // Defaulted like `googleOauthEnabled`, and to the pair this app already
    // ships copy for: a backend that predates language routing rejects the
    // `language` form field outright, and guessing a *wider* list here would
    // only produce posts it refuses.
    contentLanguages:
        (json['content_languages'] as List<dynamic>?)?.cast<String>() ??
        const ['en', 'de'],
    languageUnspecified: json['language_unspecified'] as String? ?? 'und',
  );

  /// Whether an unverified account is actually blocked from feed/channel/item
  /// actions right now - is_verified can legitimately stay false forever with
  /// this off, so the router must not force the verify-email screen unless
  /// this is true. See backend `app.deps.users.CurrentVerifiedUser`.
  final bool requireEmailVerification;
  final bool requireStrongPassword;
  final int passwordMinLength;
  final int passwordMinCharacterClasses;
  final int emailVerificationResendCooldownSeconds;

  /// Whether the backend will actually accept a Google ID token right now. The
  /// Google button stays hidden unless this and a build-time client ID
  /// (`AppConfig.googleServerClientId`) are both present.
  final bool googleOauthEnabled;

  /// The languages a post may be written in, in the order the picker should
  /// offer them. Served rather than hardcoded so that the picker, the candidate
  /// set the on-device detector may answer with, and the values `POST /posts`
  /// will accept cannot drift apart — adding a language becomes a backend
  /// setting plus a stopword list, not an app release.
  ///
  /// Note this is **not** the same list as `supportedAppLocales`
  /// (`core/settings/locale_settings.dart`), which is the languages this app's
  /// own interface is translated into. The two are separate on the backend too
  /// (`CONTENT_LANGUAGES` vs `SUPPORTED_LOCALES`) and are free to diverge.
  final List<String> contentLanguages;

  /// The reserved value meaning "this post has no language at all" — a photo, a
  /// caption-free meme. Such a post reaches every subscriber of its channel
  /// rather than one language's readers, and the backend only accepts it for a
  /// post with no text blocks.
  final String languageUnspecified;
}
