class Channel {
  Channel({
    required this.id,
    required this.name,
    required this.color,
    required this.description,
    required this.isSubscribed,
    this.postPriceMin,
    this.postPriceMax,
  });

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
    id: json['id'] as int,
    name: json['name'] as String,
    color: json['color'] as String,
    description: json['description'] as String,
    isSubscribed: json['is_subscribed'] as bool,
    // Nullable for the same reason as `Economy.postPriceExpiresAt`: a channel
    // list cached on disk before this existed carries no price. Null means
    // "unknown", never "free" — the price display skips those rows rather than
    // quoting a number nothing stands behind.
    postPriceMin: json['post_price_min'] as int?,
    postPriceMax: json['post_price_max'] as int?,
  );

  final int id;
  final String name;
  final String color;
  final String description;
  final bool isSubscribed;

  /// What publishing here costs right now, as a **range** rather than one
  /// number.
  ///
  /// A channel is several routes — one per content language, plus the
  /// no-language one — and the backend prices each by its own congestion, so
  /// there is no single figure a channel can quote (see the backend's
  /// `service.route_prices`). The exact charge exists only once an author has
  /// picked a language, and comes from `GET /posts/price`
  /// (`ChannelsRepository.fetchPostPrice`).
  ///
  /// Both ends are frequently the same number and that is the formula working:
  /// every route is held within ±50% of the shared base price, which rounds
  /// away entirely at the bottom of the scale.
  final int? postPriceMin;
  final int? postPriceMax;

  /// True when the range collapses to one number, so the UI can render "4"
  /// instead of "4–4". Also true when only one end is known, which is what a
  /// half-populated cache entry looks like.
  bool get hasSinglePrice => postPriceMin == postPriceMax;

  /// The cheapest this channel can be, for the affordability hint. The composer
  /// quotes the exact route price once a language is chosen; before that, the
  /// low end is the honest thing to check a balance against — telling someone
  /// they cannot afford a post they *could* afford in another language would be
  /// wrong, and the exact number arrives before they can publish anyway.
  int? get lowestPrice => postPriceMin ?? postPriceMax;

  Channel copyWith({bool? isSubscribed}) => Channel(
    id: id,
    name: name,
    color: color,
    description: description,
    isSubscribed: isSubscribed ?? this.isSubscribed,
    postPriceMin: postPriceMin,
    postPriceMax: postPriceMax,
  );
}

/// The exact admission price for one (channel, language) route.
///
/// A quote, not an estimate: `POST /posts` charges this number for this route
/// until [expiresAt], because both read the same cached route price for the
/// same window. That guarantee is the whole reason the composer asks for it
/// rather than interpolating inside the channel's range.
class PostPrice {
  const PostPrice({required this.price, required this.expiresAt});

  factory PostPrice.fromJson(Map<String, dynamic> json) => PostPrice(
    price: json['price'] as int,
    expiresAt: DateTime.parse(json['expires_at'] as String),
  );

  final int price;
  final DateTime expiresAt;
}
