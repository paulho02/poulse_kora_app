/// The viewer's posting economy: spendable tokens (earned by reviewing) and the
/// shared price to publish one original post (rises with backend queue
/// congestion, refreshed periodically server-side rather than computed live).
class Economy {
  const Economy({
    required this.tokenBalance,
    required this.postPrice,
    this.postPriceExpiresAt,
  });

  factory Economy.fromJson(Map<String, dynamic> json) => Economy(
    tokenBalance: json['token_balance'] as int,
    postPrice: json['post_price'] as int,
    // Nullable: a JSON blob cached on disk before this field existed won't have
    // it, and the countdown just doesn't render for that stale entry.
    postPriceExpiresAt: json['post_price_expires_at'] != null
        ? DateTime.parse(json['post_price_expires_at'] as String)
        : null,
  );

  final int tokenBalance;
  final int postPrice;
  final DateTime? postPriceExpiresAt;

  bool get canAffordPost => tokenBalance >= postPrice;

  Economy copyWith({
    int? tokenBalance,
    int? postPrice,
    DateTime? postPriceExpiresAt,
  }) => Economy(
    tokenBalance: tokenBalance ?? this.tokenBalance,
    postPrice: postPrice ?? this.postPrice,
    postPriceExpiresAt: postPriceExpiresAt ?? this.postPriceExpiresAt,
  );
}
