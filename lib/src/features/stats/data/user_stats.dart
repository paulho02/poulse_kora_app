class WeeklyActivityBucket {
  WeeklyActivityBucket({required this.date, required this.count});

  factory WeeklyActivityBucket.fromJson(Map<String, dynamic> json) =>
      WeeklyActivityBucket(
        date: DateTime.parse(json['date'] as String),
        count: json['count'] as int,
      );

  final DateTime date;
  final int count;
}

class Badge {
  Badge({required this.code, required this.label, required this.earned});

  factory Badge.fromJson(Map<String, dynamic> json) => Badge(
    code: json['code'] as String,
    label: json['label'] as String,
    earned: json['earned'] as bool,
  );

  final String code;
  final String label;
  final bool earned;
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
    required this.avgHops,
    required this.weeklyActivity,
    required this.badges,
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
    avgHops: (json['avg_hops'] as num).toDouble(),
    weeklyActivity: (json['weekly_activity'] as List<dynamic>)
        .map((j) => WeeklyActivityBucket.fromJson(j as Map<String, dynamic>))
        .toList(),
    badges: (json['badges'] as List<dynamic>)
        .map((j) => Badge.fromJson(j as Map<String, dynamic>))
        .toList(),
    reviewGate: json['review_gate'] as int,
    unlocked: json['unlocked'] as bool,
  );

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

  final double avgHops;
  final List<WeeklyActivityBucket> weeklyActivity;
  final List<Badge> badges;
  final int reviewGate;
  final bool unlocked;
}
