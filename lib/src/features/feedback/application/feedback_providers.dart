import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/feedback_repository.dart';

/// No `jsonCacheProvider` here, unlike the other repositories: feedback is
/// write-only from the app's side, and a write is never replayed from cache
/// (`core/cache/cached_fetch.dart`'s rule) — a failed submission is retried by
/// the person who wrote it, with the text still in the field.
final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  return FeedbackRepository(ref.watch(dioClientProvider).dio);
});
