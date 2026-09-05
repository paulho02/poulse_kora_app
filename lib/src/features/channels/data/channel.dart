class Channel {
  Channel({
    required this.id,
    required this.name,
    required this.color,
    required this.description,
    required this.isSubscribed,
    this.postPrice,
  });

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
    id: json['id'] as int,
    name: json['name'] as String,
    color: json['color'] as String,
    description: json['description'] as String,
    isSubscribed: json['is_subscribed'] as bool,
    // Nullable for the same reason as `Economy.postPriceExpiresAt`: a channel
    // list cached on disk before per-channel pricing existed carries no price.
    // Null means "unknown", never "free" — the price display skips those rows
    // rather than quoting a number nothing stands behind.
    postPrice: json['post_price'] as int?,
  );

  final int id;
  final String name;
  final String color;
  final String description;
  final bool isSubscribed;

  /// What publishing here costs right now, quoted by the backend and held for
  /// the current price window — the exact number `POST /posts` will charge (see
  /// the backend's `service.channel_prices`), not an estimate.
  final int? postPrice;

  Channel copyWith({bool? isSubscribed}) => Channel(
    id: id,
    name: name,
    color: color,
    description: description,
    isSubscribed: isSubscribed ?? this.isSubscribed,
    postPrice: postPrice,
  );
}
