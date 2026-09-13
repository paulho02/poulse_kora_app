/// The viewer's posting economy: spendable tokens (earned by reviewing) and
/// what publishing one original post costs across the deployment (rises with
/// backend queue congestion, refreshed periodically server-side rather than
/// computed live).
class Economy {
  const Economy({
    required this.tokenBalance,
    required this.postPrice,
    this.postPriceMin,
    this.postPriceMax,
    this.postPriceExpiresAt,
  });

  factory Economy.fromJson(Map<String, dynamic> json) => Economy(
    tokenBalance: json['token_balance'] as int,
    postPrice: json['post_price'] as int,
    // Null on a blob cached before per-route pricing; `priceRange` falls back
    // to the base price at both ends, which is also what the backend reports
    // when nothing has been observed in the current window yet.
    postPriceMin: json['post_price_min'] as int?,
    postPriceMax: json['post_price_max'] as int?,
    // Nullable: a JSON blob cached on disk before this field existed won't have
    // it, and the countdown just doesn't render for that stale entry.
    postPriceExpiresAt: json['post_price_expires_at'] != null
        ? DateTime.parse(json['post_price_expires_at'] as String)
        : null,
  );

  final int tokenBalance;

  /// The shared *base* rate. No longer what anyone is charged — every (channel,
  /// language) route scales it by its own congestion — but it is what the range
  /// is centred on, and what both ends collapse to before any route has been
  /// priced in the current window.
  final int postPrice;

  /// The cheapest and dearest route anyone has priced this window (see the
  /// backend's `keys.PRICE_RANGE`). Null only on a stale cache entry.
  final int? postPriceMin;
  final int? postPriceMax;

  final DateTime? postPriceExpiresAt;

  /// The range to display, with the base price standing in for either end that
  /// is unknown. Never null, so the pill always has something to draw.
  (int, int) get priceRange => (
    postPriceMin ?? postPrice,
    postPriceMax ?? postPrice,
  );

  /// True when the range is one number, so the UI renders "4" and not "4–4".
  bool get hasSinglePrice => priceRange.$1 == priceRange.$2;

  /// Whether *any* post is affordable — checked against the cheapest route,
  /// because the alternative tells someone they cannot post when a different
  /// channel or language would in fact be within reach. The composer replaces
  /// this with the exact route price the moment one is selectable.
  bool get canAffordPost => tokenBalance >= priceRange.$1;

  Economy copyWith({
    int? tokenBalance,
    int? postPrice,
    int? postPriceMin,
    int? postPriceMax,
    DateTime? postPriceExpiresAt,
  }) => Economy(
    tokenBalance: tokenBalance ?? this.tokenBalance,
    postPrice: postPrice ?? this.postPrice,
    postPriceMin: postPriceMin ?? this.postPriceMin,
    postPriceMax: postPriceMax ?? this.postPriceMax,
    postPriceExpiresAt: postPriceExpiresAt ?? this.postPriceExpiresAt,
  );
}
