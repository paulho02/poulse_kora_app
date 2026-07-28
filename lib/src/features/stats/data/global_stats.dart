class ForwardingBucket {
  ForwardingBucket({required this.label, required this.postCount});

  factory ForwardingBucket.fromJson(Map<String, dynamic> json) =>
      ForwardingBucket(
        label: json['label'] as String,
        postCount: json['post_count'] as int,
      );

  final String label;
  final int postCount;
}

class GlobalStats {
  GlobalStats({required this.totalPosts, required this.forwardingDistribution});

  factory GlobalStats.fromJson(Map<String, dynamic> json) => GlobalStats(
    totalPosts: json['total_posts'] as int,
    forwardingDistribution: (json['forwarding_distribution'] as List<dynamic>)
        .map((j) => ForwardingBucket.fromJson(j as Map<String, dynamic>))
        .toList(),
  );

  final int totalPosts;
  final List<ForwardingBucket> forwardingDistribution;
}
