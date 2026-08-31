import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../config/app_config.dart';
import '../../providers.dart';
import 'blob_url_stub.dart' if (dart.library.js_interop) 'blob_url_web.dart'
    as blob_url;

/// A playable video, plus how to release whatever platform resource backs it
/// once the caller is done (only meaningful on web - see below; mobile/desktop
/// leave [dispose] null).
class VideoSource {
  VideoSource(this.controller, [this.dispose]);

  final VideoPlayerController controller;
  final void Function()? dispose;
}

/// Builds a ready-to-initialize video source for a post's video
/// (`PostMediaRead.url` where `media_type` is `"video"`).
///
/// Two different strategies, by platform:
///
/// - **Mobile/desktop**: `video_player` requests the URL itself, progressively,
///   via native Range requests (see `GET /posts/{post_id}/media/{media_id}` on
///   the backend, which exists specifically to support that) - pre-fetching the
///   whole clip into memory first would defeat the point of that. The bearer
///   token goes on as a normal `Authorization` header, same as any other API
///   call.
/// - **Web**: a browser's native `<video>` element has no mechanism to attach a
///   custom header to the request it issues for its `src` - this is a platform
///   limitation, not something `video_player_web` can work around. So on web
///   the (size-capped - see `POST_VIDEO_MAX_BYTES`) bytes are fetched once
///   through the authenticated Dio client, exactly like a post image, and handed
///   to the player as a local `blob:` URL, which needs no auth at all.
Future<VideoSource> videoSourceFor(WidgetRef ref, String mediaUrl) async {
  if (kIsWeb) {
    final dio = ref.read(dioClientProvider).dio;
    final response = await dio.get<List<int>>(
      _toApiRelativePath(mediaUrl),
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = Uint8List.fromList(response.data ?? const []);
    final url = blob_url.createBlobUrl(bytes, 'video/mp4');
    return VideoSource(
      VideoPlayerController.networkUrl(Uri.parse(url)),
      () => blob_url.revokeBlobUrl(url),
    );
  }

  final token = await ref.read(tokenStorageProvider).readAccessToken();
  final uri = Uri.parse('${AppConfig.apiBaseUrl}$mediaUrl');
  return VideoSource(
    VideoPlayerController.networkUrl(
      uri,
      httpHeaders: {if (token != null) 'Authorization': 'Bearer $token'},
    ),
  );
}

/// Mirrors `AuthenticatedByteCache._toApiRelativePath`: the backend returns an
/// absolute API path, but Dio's `baseUrl` already ends in the same prefix.
String _toApiRelativePath(String url) =>
    url.startsWith(AppConfig.apiPath)
    ? url.substring(AppConfig.apiPath.length)
    : url;
