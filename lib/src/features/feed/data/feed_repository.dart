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
  ComposerBlockInput.text(this.text) : type = 'text', mediaIndex = null;
  ComposerBlockInput.media(this.mediaIndex) : type = 'media', text = null;

  final String type;
  final String? text;
  final int? mediaIndex;

  Map<String, dynamic> toJson() => type == 'text'
      ? {'type': 'text', 'text': text}
      : {'type': 'media', 'file_index': mediaIndex};
}

class PostReviewResult {
  PostReviewResult({
    required this.postId,
    required this.kind,
    required this.reviewedCount,
    required this.reviewGate,
    required this.unlocked,
    required this.tokenBalance,
  });

  factory PostReviewResult.fromJson(Map<String, dynamic> json) =>
      PostReviewResult(
        postId: json['post_id'] as int,
        kind: json['kind'] as String,
        reviewedCount: json['reviewed_count'] as int,
        reviewGate: json['review_gate'] as int,
        unlocked: json['unlocked'] as bool,
        tokenBalance: json['token_balance'] as int,
      );

  final int postId;
  final String kind;
  final int reviewedCount;
  final int reviewGate;
  final bool unlocked;

  /// Spendable balance after earning one token for this review.
  final int tokenBalance;
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
  Future<Cached<List<Post>>> fetchFeed({
    int? channelId,
    int skip = 0,
    int limit = 20,
  }) {
    return fetchCached<List<Post>>(
      cache: _cache,
      key: CacheKeys.feed(channelId),
      fetchJson: () async {
        final response = await _dio.get<List<dynamic>>(
          '/posts/feed',
          queryParameters: {
            'channel_id': ?channelId,
            'skip': skip,
            'limit': limit,
          },
        );
        return response.data!;
      },
      parse: (json) => (json as List<dynamic>)
          .map((e) => Post.fromJson(e as Map<String, dynamic>))
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
    bool isAnonymous = false,
    List<PickedMedia> media = const [],
  }) async {
    final form = FormData.fromMap({
      'channel_id': channelId.toString(),
      'blocks': jsonEncode(blocks.map((b) => b.toJson()).toList()),
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

  Future<PostReviewResult> reviewPost(int postId, String kind) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/posts/$postId/review',
      data: {'kind': kind},
    );
    return PostReviewResult.fromJson(response.data!);
  }
}
