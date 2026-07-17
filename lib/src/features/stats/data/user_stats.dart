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
  final int trustScore;
  final double avgHops;
  final List<WeeklyActivityBucket> weeklyActivity;
  final List<Badge> badges;
  final int reviewGate;
  final bool unlocked;
}
