class Channel {
  Channel({
    required this.id,
    required this.name,
    required this.color,
    required this.description,
    required this.isSubscribed,
  });

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
    id: json['id'] as int,
    name: json['name'] as String,
    color: json['color'] as String,
    description: json['description'] as String,
    isSubscribed: json['is_subscribed'] as bool,
  );

  final int id;
  final String name;
  final String color;
  final String description;
  final bool isSubscribed;

  Channel copyWith({bool? isSubscribed}) => Channel(
    id: id,
    name: name,
    color: color,
    description: description,
    isSubscribed: isSubscribed ?? this.isSubscribed,
  );
}
