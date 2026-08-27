class UserProfile {
  UserProfile({
    required this.id,
    required this.email,
    required this.username,
    required this.bio,
    required this.darkMode,
    required this.settingsRevision,
    required this.onboardingCompleted,
    required this.isVerified,
    required this.authProvider,
    required this.googleEmail,
    required this.profilePictureUrl,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    email: json['email'] as String,
    username: json['username'] as String?,
    bio: json['bio'] as String?,
    darkMode: json['dark_mode'] as bool,
    // Defaulted so a cache entry written before this field existed still
    // parses — it will simply look like revision 0 and get reconciled.
    settingsRevision: json['settings_revision'] as int? ?? 0,
    // Defaulted the same way, and to `false` specifically: a cache entry
    // written before this field existed must not be read as "onboarding
    // already done" and skip the flow.
    onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
    // Defaulted to `true`: a cache entry written before this field existed
    // belongs to a session that was already using the app normally, so it
    // must not be read as "unverified" and suddenly force the verify screen.
    isVerified: json['is_verified'] as bool? ?? true,
    // Defaulted to "password": a cache entry written before this field existed
    // belongs to an account that could only have been a password one, and
    // guessing "google" would wrongly hide the change-password entry.
    authProvider: json['auth_provider'] as String? ?? 'password',
    googleEmail: json['google_email'] as String?,
    profilePictureUrl: json['profile_picture_url'] as String?,
  );

  final String id;
  final String email;
  final String? username;
  final String? bio;
  final bool isVerified;

  /// "password" or "google" (backend `User.auth_provider`). A Google account
  /// cannot go back: its password is gone and its email is frozen, so the UI
  /// hides those affordances rather than let the user find out by being refused.
  final String authProvider;

  bool get isGoogleAccount => authProvider == 'google';

  /// Address of the linked Google account, or null if there is none.
  ///
  /// Not necessarily [email]: linking from Settings accepts any Google account,
  /// after which this is what signs you in while [email] stays the address you
  /// get contacted at.
  final String? googleEmail;

  /// True when the sign-in address and the contact address are different, which
  /// is the only case where showing both is worth the extra line.
  bool get hasDistinctGoogleEmail =>
      googleEmail != null && googleEmail!.toLowerCase() != email.toLowerCase();

  /// Where to fetch this account's profile picture, or null if it has none.
  ///
  /// An API path rather than the bytes themselves — the route needs the bearer
  /// token, so it is loaded through [AvatarCache] rather than `Image.network`.
  /// The path is derived from the user id, so it does *not* change when the
  /// picture is replaced; [AvatarCache.evict] is what makes a new upload show up.
  final String? profilePictureUrl;

  /// The server's copy of the preference. Note this is *not* what the app renders
  /// from — see `core/settings/app_settings.dart`. It is only an input to sync.
  final bool darkMode;

  /// Server-side counter, bumped only when a settings field changes value.
  /// Lets the app tell "nobody else touched this" from "another device did".
  final int settingsRevision;

  /// Whether the one-time post-registration onboarding flow (intro slides,
  /// channel picks, disclaimer) has been confirmed. Drives the `/onboarding`
  /// redirect in `routing/app_router.dart`.
  final bool onboardingCompleted;

  UserProfile copyWith({
    String? bio,
    bool? darkMode,
    int? settingsRevision,
    bool? onboardingCompleted,
  }) => UserProfile(
    id: id,
    email: email,
    username: username,
    authProvider: authProvider,
    googleEmail: googleEmail,
    // Not a parameter: clearing a picture goes through the server and comes back
    // as a fresh profile, so there is no case where copyWith needs to null it.
    profilePictureUrl: profilePictureUrl,
    bio: bio ?? this.bio,
    darkMode: darkMode ?? this.darkMode,
    settingsRevision: settingsRevision ?? this.settingsRevision,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    isVerified: isVerified,
  );
}
