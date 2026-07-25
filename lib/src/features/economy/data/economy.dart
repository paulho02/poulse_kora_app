/// The viewer's posting economy: spendable tokens (earned by reviewing) and the
/// live price to publish one original post (rises with backend queue congestion).
class Economy {
  const Economy({required this.tokenBalance, required this.postPrice});

  factory Economy.fromJson(Map<String, dynamic> json) => Economy(
    tokenBalance: json['token_balance'] as int,
    postPrice: json['post_price'] as int,
  );

  final int tokenBalance;
  final int postPrice;

  bool get canAffordPost => tokenBalance >= postPrice;

  Economy copyWith({int? tokenBalance, int? postPrice}) => Economy(
    tokenBalance: tokenBalance ?? this.tokenBalance,
    postPrice: postPrice ?? this.postPrice,
  );
}
