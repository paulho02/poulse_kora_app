import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/cache/cached.dart';
import '../../../core/cache/cached_fetch.dart';
import '../../../core/cache/json_cache.dart';
import 'post.dart';

/// One image or video picked in the composer, ready to upload — see
/// `create_post/presentation/create_post_screen.dart`.
class PickedMedia {
  PickedMedia({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
}

/// One block of a post being composed - mirrors the backend's `PostBlockIn`.
/// A media block names its index into the parallel `media: List<PickedMedia>`
/// passed to `FeedRepository.createPost`, not the bytes themselves.
class ComposerBlockInput {
  ComposerBlockInput.text(this.text)
    : type = 'text',
      mediaIndex = null,
      orientation = null;
  ComposerBlockInput.media(this.mediaIndex, {this.orientation})
    : type = 'media',
      text = null;

  final String type;
  final String? text;
  final int? mediaIndex;

  /// `"landscape"` / `"portrait"`, and only meaningful for a **video**: the
  /// backend center-crops the clip to that shape inside the transcode it runs
  /// anyway, because a Flutter client cannot re-encode video. A photo is
  /// cropped locally before upload and its shape is already final, so this is
  /// ignored for one.
  final String? orientation;

  Map<String, dynamic> toJson() => type == 'text'
      ? {'type': 'text', 'text': text}
      : {
          'type': 'media',
          'file_index': mediaIndex,
          if (orientation != null) 'orientation': orientation,
        };
}

/// A cheap look at the server-side review queue: which posts are in it, and how
/// many it can ever hold.
class FeedQueueStatus {
  const FeedQueueStatus({required this.postIds, required this.capacity});

  factory FeedQueueStatus.fromJson(Map<String, dynamic> json) =>
      FeedQueueStatus(
        postIds: (json['post_ids'] as List<dynamic>).cast<int>(),
        capacity: json['capacity'] as int,
      );

  /// The whole queue, in the order the feed renders it. Ids rather than a count
  /// so a client that remembers what it has already pulled can tell "something
  /// new arrived" from "the same posts, minus the ones I reviewed" exactly, and
  /// so never fetches the feed for nothing.
  final List<int> postIds;

  /// The queue's server-side cap. What separates "nothing has been published for
  /// you yet" from "your queue is full" — opposite things to tell a reader, and
  /// the second also means no arrival is possible until they review something.
  final int capacity;

  bool get isFull => postIds.length >= capacity;
}

class PostReviewResult {
  PostReviewResult({
    required this.postId,
    required this.kind,
    required this.reviewedCount,
    required this.reviewGate,
    required this.unlocked,
    required this.tokenBalance,
    required this.postForwardedCount,
    required this.postReviewedCount,
    this.isProbe = false,
    this.probeCorrect,
  });

  factory PostReviewResult.fromJson(Map<String, dynamic> json) =>
      PostReviewResult(
        postId: json['post_id'] as int,
        kind: json['kind'] as String,
        reviewedCount: json['reviewed_count'] as int,
        reviewGate: json['review_gate'] as int,
        unlocked: json['unlocked'] as bool,
        tokenBalance: json['token_balance'] as int,
        postForwardedCount: json['post_forwarded_count'] as int,
        postReviewedCount: json['post_reviewed_count'] as int,
        isProbe: json['is_probe'] as bool? ?? false,
        probeCorrect: json['probe_correct'] as bool?,
      );

  final int postId;
  final String kind;
  final int reviewedCount;
  final int reviewGate;
  final bool unlocked;

  /// Spendable balance after earning one token for this review.
  final int tokenBalance;

  /// How the post itself has fared, counting this review. Deliberately absent
  /// from [Post]: the server discloses it only here, once the reader has
  /// committed to their own verdict, so the crowd cannot cast it.
  /// [postReviewedCount] is everyone who forwarded *or* dropped it - the
  /// denominator, so "2 of 9" can be shown rather than a bare count.
  final int postForwardedCount;
  final int postReviewedCount;

  /// Whether the post just reviewed was a trust check (see [Post.isProbe]).
  /// The two counts above are zeroed for one and must not be shown: a probe is
  /// created for a single reader, so its score could only ever read "1 of 1".
  final bool isProbe;

  /// Whether the check was answered as it asked, or null when there was nothing
  /// to score (an ordinary post, or a probe whose wording the server no longer
  /// recognises). Shown to the reader rather than kept quiet — otherwise the
  /// only feedback a careless reader ever gets is reach quietly disappearing.
  final bool? probeCorrect;
}

/// Result of publishing an original post: the created post plus what it cost.
class CreatePostResult {
  CreatePostResult({
    required this.post,
    required this.price,
    required this.tokenBalance,
  });

  factory CreatePostResult.fromJson(Map<String, dynamic> json) =>
      CreatePostResult(
        post: Post.fromJson(json['post'] as Map<String, dynamic>),
        price: json['price'] as int,
        tokenBalance: json['token_balance'] as int,
      );

  final Post post;
  final int price;

  /// Spendable balance after paying the post's price.
  final int tokenBalance;
}

/// Shared between the Feed and Create-Post features — both operate on the
/// same `/posts` resource.
class FeedRepository {
  FeedRepository(this._dio, this._cache);

  final Dio _dio;
  final JsonCache _cache;

  /// Reads fall back to the last cached queue when the backend is unreachable, so
  /// an offline user can still read what they had. Writes below deliberately do
  /// not queue: reviewing is guarded server-side by the Redis queue and posting is
  /// priced at request time, so a deferred replay could fail or overcharge long
  /// after the user believed it succeeded.
  ///
  /// Answers [FeedEntry], not [Post]: a slot whose post has been erased comes
  /// back as a [MissingPost] rather than being left out, so the reader can see
  /// why the queue is not filling up and clear the slot. A cache entry written
  /// before that shape existed simply fails to parse and is discarded as a miss
  /// (see `JsonCache.read`).
  Future<Cached<List<FeedEntry>>> fetchFeed({int? channelId}) {
    return fetchCached<List<FeedEntry>>(
      cache: _cache,
      key: CacheKeys.feed(channelId),
      fetchJson: () async {
        // No `skip`/`limit`: the review queue is capped server-side
        // (FEED_QUEUE_MAX_SLOTS) and the backend defaults `limit` to that cap, so
        // one request is always the whole queue. Paging it would be worse than
        // pointless — holding only part of it, the top-up below could not tell a
        // post that just arrived from one it had simply never asked for, and would
        // refetch on every poll forever.
        final response = await _dio.get<List<dynamic>>(
          '/posts/feed',
          queryParameters: {'channel_id': ?channelId},
        );
        return response.data!;
      },
      parse: (json) => (json as List<dynamic>)
          .map((e) => FeedEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// `POST /posts` is multipart on the backend (it accepts up to
  /// POST_MEDIA_MAX_FILES image/video attachments in one request/one
  /// transaction — see the backend's app/api/posts.py), so this always sends a
  /// multipart body, media or not. `blocks` is itself a JSON-encoded list (a
  /// `Form` field, not a file) - multipart has no native way to carry a nested
  /// list of objects; the backend parses it back with the same shape.
  Future<CreatePostResult> createPost({
    required int channelId,
    required List<ComposerBlockInput> blocks,
    required String language,
    bool isAnonymous = false,
    List<PickedMedia> media = const [],
  }) async {
    final form = FormData.fromMap({
      'channel_id': channelId.toString(),
      'blocks': jsonEncode(blocks.map((b) => b.toJson()).toList()),
      // Required, not defaulted: with `channel_id` this is the routing key that
      // decides who can receive the post (see the backend's `keys.audience`).
      // A default here would be a silent guess on the one field whose wrong
      // value sends the post to people who cannot read it.
      'language': language,
      'is_anonymous': isAnonymous.toString(),
    });
    // `form.files.add(...)`, not another `FormData.fromMap` entry: repeated
    // keys in a map collapse, and the backend expects every file under the
    // same repeated "files" field.
    for (final item in media) {
      form.files.add(
        MapEntry(
          'files',
          MultipartFile.fromBytes(
            item.bytes,
            filename: item.filename,
            contentType: DioMediaType.parse(item.contentType),
          ),
        ),
      );
    }
    final response = await _dio.post<Map<String, dynamic>>(
      '/posts',
      data: form,
    );
    return CreatePostResult.fromJson(response.data!);
  }

  /// What is in the review queue right now, without rendering any of it — the
  /// poll behind the feed topping itself up (see the backend's
  /// `GET /posts/feed/status`).
  ///
  /// Deliberately *not* cached: this is the question the cache exists to answer
  /// cheaply, and a disk copy replayed as an answer would have the feed announce
  /// arrivals that are not there. A caller treats a failure as "no news" and asks
  /// again on the next tick.
  Future<FeedQueueStatus> fetchFeedStatus() async {
    final response = await _dio.get<Map<String, dynamic>>('/posts/feed/status');
    return FeedQueueStatus.fromJson(response.data!);
  }

  Future<PostReviewResult> reviewPost(int postId, String kind) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/posts/$postId/review',
      data: {'kind': kind},
    );
    return PostReviewResult.fromJson(response.data!);
  }

  /// Clear a queue slot whose post no longer exists — the ghost card's one
  /// button (see [MissingPost]).
  ///
  /// Deliberately not `reviewPost(id, 'drop')`: nothing was read, so there is no
  /// verdict to record and no token to earn, and the backend refuses this while
  /// the post still exists so it cannot become a way to skip one. It answers 409
  /// `post_available` in that case, which means this client's list is stale
  /// rather than that anything went wrong.
  Future<void> dismissMissingPost(int postId) async {
    await _dio.delete<void>('/posts/feed/$postId');
  }
}
