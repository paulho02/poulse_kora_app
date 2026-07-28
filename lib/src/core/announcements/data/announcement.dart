/// A superuser-pushed announcement (see backend `GET /banner`). Plain text only.
class Announcement {
  const Announcement({required this.id, required this.message});

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
    id: json['id'] as String,
    message: json['message'] as String,
  );

  /// Opaque — never parsed, only compared for equality against a dismissal id.
  final String id;
  final String message;
}
