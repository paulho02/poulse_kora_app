class UserProfile {
  UserProfile({
    required this.id,
    required this.email,
    required this.username,
    required this.bio,
    required this.darkMode,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        email: json['email'] as String,
        username: json['username'] as String?,
        bio: json['bio'] as String?,
        darkMode: json['dark_mode'] as bool,
      );

  final String id;
  final String email;
  final String? username;
  final String? bio;
  final bool darkMode;

  UserProfile copyWith({String? bio, bool? darkMode}) => UserProfile(
        id: id,
        email: email,
        username: username,
        bio: bio ?? this.bio,
        darkMode: darkMode ?? this.darkMode,
      );
}
