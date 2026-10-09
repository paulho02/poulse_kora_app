/// The four review numbers over one span — all time, or the last 7 days. The
/// stats screen's Total / 7 days switch flips between two of these.
class ReviewTotals {
  const ReviewTotals({
    required this.reviewedCount,
    required this.forwardedCount,
    required this.droppedCount,
    required this.forwardRate,
  });

  /// Tolerates a missing block: an offline start can parse a stats payload
  /// cached before `this_week` existed, and zeros beat failing the screen.
  factory ReviewTotals.fromJson(Map<String, dynamic>? json) => ReviewTotals(
    reviewedCount: json?['reviewed_count'] as int? ?? 0,
    forwardedCount: json?['forwarded_count'] as int? ?? 0,
    droppedCount: json?['dropped_count'] as int? ?? 0,
    forwardRate: (json?['forward_rate'] as num?)?.toDouble() ?? 0,
  );

  final int reviewedCount;
  final int forwardedCount;
  final int droppedCount;

  /// Share of reviews that were forwards, 0.0–1.0.
  final double forwardRate;
}

class UserStats {
  UserStats({
    required this.reviewedCount,
    required this.forwardedCount,
    required this.droppedCount,
    required this.createdPostCount,
    required this.trustScore,
    required this.trustBand,
    required this.trustFanout,
    required this.trustReachMultiplier,
    required this.trustWindowDays,
    required this.forwardRate,
    required this.thisWeek,
    required this.reviewGate,
    required this.unlocked,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) => UserStats(
    reviewedCount: json['reviewed_count'] as int,
    forwardedCount: json['forwarded_count'] as int,
    droppedCount: json['dropped_count'] as int,
    createdPostCount: json['created_post_count'] as int,
    trustScore: json['trust_score'] as int,
    trustBand: json['trust_band'] as String? ?? 'normal',
    trustFanout: json['trust_fanout'] as int? ?? 0,
    trustReachMultiplier:
        (json['trust_reach_multiplier'] as num?)?.toDouble() ?? 1,
    trustWindowDays: json['trust_window_days'] as int? ?? 30,
    // `avg_hops` is the same number under its old name, still in caches
    // written before the rename.
    forwardRate:
        ((json['forward_rate'] ?? json['avg_hops']) as num?)?.toDouble() ?? 0,
    thisWeek: ReviewTotals.fromJson(json['this_week'] as Map<String, dynamic>?),
    reviewGate: json['review_gate'] as int,
    unlocked: json['unlocked'] as bool,
  );

  /// All-time; [thisWeek] holds the same numbers for the last 7 days.
  final int reviewedCount;
  final int forwardedCount;
  final int droppedCount;
  final int createdPostCount;

  /// Reviewer Trust, 0-100 — how carefully this account has been reading
  /// *recently* (see [trustWindowDays]), not a lifetime record.
  final int trustScore;

  /// Which reach band the score falls in: "low" | "normal" | "high". A stable
  /// code, not a label — the words come from the .arb, the same contract the
  /// API's error codes use.
  final String trustBand;

  /// People one of this account's forwards now reaches, and that as a multiple
  /// of the standard reach. The explainer shows these rather than the score
  /// alone, because "your forwards reach 4 people instead of 3" is the only
  /// form of the sentence a reader can act on.
  final int trustFanout;
  final double trustReachMultiplier;

  /// How far back the score looks. Everything older is invisible to it, which
  /// is why a bad stretch heals and a good one has to be kept up.
  final int trustWindowDays;

  final double forwardRate;
  final ReviewTotals thisWeek;
  final int reviewGate;
  final bool unlocked;

  /// The all-time numbers in the same shape as [thisWeek].
  ReviewTotals get allTime => ReviewTotals(
    reviewedCount: reviewedCount,
    forwardedCount: forwardedCount,
    droppedCount: droppedCount,
    forwardRate: forwardRate,
  );
}
