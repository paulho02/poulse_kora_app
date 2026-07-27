class UserProfile {
  UserProfile({
    required this.id,
    required this.email,
    required this.username,
    required this.bio,
    required this.darkMode,
    required this.settingsRevision,
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
      );

  final String id;
  final String email;
  final String? username;
  final String? bio;

  /// The server's copy of the preference. Note this is *not* what the app renders
  /// from — see `core/settings/app_settings.dart`. It is only an input to sync.
  final bool darkMode;

  /// Server-side counter, bumped only when a settings field changes value.
  /// Lets the app tell "nobody else touched this" from "another device did".
  final int settingsRevision;

  UserProfile copyWith({String? bio, bool? darkMode, int? settingsRevision}) =>
      UserProfile(
        id: id,
        email: email,
        username: username,
        bio: bio ?? this.bio,
        darkMode: darkMode ?? this.darkMode,
        settingsRevision: settingsRevision ?? this.settingsRevision,
      );
}
