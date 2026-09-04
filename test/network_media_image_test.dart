import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/src/core/avatars/presentation/user_avatar.dart';
import 'package:poulse_kora_app/src/core/media/application/media_reload.dart';
import 'package:poulse_kora_app/src/core/media/presentation/network_media_image.dart';

/// Replaces the old `authenticated_byte_cache_test.dart`. What that file
/// protected — one fetch per URL, failures not retried into a storm, a replaced
/// picture actually appearing — is now either Flutter's job (`ImageCache`) or
/// gone entirely (a replaced picture is a different URL). What is left worth
/// pinning is the contract with the backend's presigned URLs, and one part of it
/// would break silently rather than loudly: **no `Authorization` header may go
/// out, and the URL must travel verbatim**. S3 rejects a request carrying both a
/// query signature and an auth header, and the signature covers the path and
/// query, so re-adding the token or re-deriving the path would not look wrong in
/// review — it would 403 every image in the app.
///
/// Assertions here are about *what is requested*, not about decoded pixels:
/// image decoding needs real async that a widget test's fake clock cannot pump,
/// so "did it paint" tests would only be testing `tester.runAsync`.

/// Records every request the image loader makes.
///
/// Installed through `debugNetworkImageHttpClientProvider`, not `HttpOverrides`:
/// `NetworkImage` holds its `HttpClient` in a **static final**, so it is built
/// once from whatever overrides were in effect for the first test that loaded an
/// image and every later test keeps talking to that one. The debug hook is
/// consulted per request, which is the only thing that actually varies per test.
class _Recorder {
  final requestedUrls = <Uri>[];
  final headerNames = <String>[];
  var statusCode = 200;
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.overrides);

  final _Recorder overrides;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    overrides.requestedUrls.add(url);
    return _FakeHttpClientRequest(overrides, url);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this.overrides, this.uri);

  final _Recorder overrides;

  @override
  final Uri uri;

  @override
  final HttpHeaders headers = _RecordingHeaders();

  @override
  Future<HttpClientResponse> close() async {
    overrides.headerNames.addAll((headers as _RecordingHeaders).names);
    return _FakeHttpClientResponse(overrides.statusCode);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingHeaders implements HttpHeaders {
  final names = <String>[];

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      names.add(name.toLowerCase());

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      names.add(name.toLowerCase());

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientResponse implements HttpClientResponse {
  _FakeHttpClientResponse(this.statusCode);

  @override
  final int statusCode;

  @override
  int get contentLength => 0;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(Uint8List(0)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _host(Widget child, ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// The URL the mounted [Image] was actually given.
String _resolvedUrl(WidgetTester tester) =>
    (tester.widget<Image>(find.byType(Image)).image as NetworkImage).url;

/// Runs [body] with image loading pointed at [recorder], and unset again
/// afterwards.
///
/// The reset has to happen inside the test body, not in a `tearDown`:
/// flutter_test asserts that every painting debug variable is null as the last
/// step of running the body itself, so a teardown would always be too late.
Future<void> _recordingNetwork(
  _Recorder recorder,
  Future<void> Function() body,
) async {
  debugNetworkImageHttpClientProvider = () => _FakeHttpClient(recorder);
  try {
    await body();
  } finally {
    debugNetworkImageHttpClientProvider = null;
  }
}

void main() {
  late _Recorder overrides;
  late ProviderContainer container;

  setUp(() {
    overrides = _Recorder();
    container = ProviderContainer();
    PaintingBinding.instance.imageCache.clear();
  });

  tearDown(() => container.dispose());

  group('NetworkMediaImage', () {
    testWidgets('requests the URL verbatim, with no Authorization header', (
      tester,
    ) async {
      await _recordingNetwork(overrides, () async {
        const url =
            'https://bucket.example/post-media/abc.jpg?X-Amz-Signature=deadbeef';
        await tester.pumpWidget(
          _host(
            const SizedBox(
              width: 40,
              height: 40,
              child: NetworkMediaImage(url: url, fallback: SizedBox.shrink()),
            ),
            container,
          ),
        );
        await tester.pump();

        // Verbatim, query string included: the signature covers both the path and
        // the query. This is also why a media URL is never treated as
        // API-relative any more, the way it had to be when it pointed at us.
        expect(overrides.requestedUrls.single.toString(), url);
        expect(overrides.headerNames, isNot(contains('authorization')));
        expect(_resolvedUrl(tester), url);
      });
    });

    testWidgets('shows the fallback before any bytes arrive', (tester) async {
      await _recordingNetwork(overrides, () async {
        await tester.pumpWidget(
          _host(
            const SizedBox(
              width: 40,
              height: 40,
              child: NetworkMediaImage(
                url: 'https://bucket.example/a.jpg',
                fallback: Text('placeholder'),
              ),
            ),
            container,
          ),
        );

        // No spinner, here or ever: media is decoration around content that reads
        // fine without it, and a feed full of spinners jitters on every scroll.
        expect(find.text('placeholder'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      });
    });

    testWidgets('an expired or refused URL degrades to the fallback', (
      tester,
    ) async {
      await _recordingNetwork(overrides, () async {
        overrides.statusCode = 403;
        await tester.pumpWidget(
          _host(
            const SizedBox(
              width: 40,
              height: 40,
              child: NetworkMediaImage(
                url: 'https://bucket.example/expired.jpg',
                fallback: Text('placeholder'),
              ),
            ),
            container,
          ),
        );
        await tester.pumpAndSettle();

        // A signature outliving its window must look like a missing picture, not
        // like an exception in the middle of a feed.
        expect(find.text('placeholder'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a media reload re-resolves the same URL', (tester) async {
      await _recordingNetwork(overrides, () async {
        await tester.pumpWidget(
          _host(
            const SizedBox(
              width: 40,
              height: 40,
              child: NetworkMediaImage(
                url: 'https://bucket.example/a.jpg',
                fallback: SizedBox.shrink(),
              ),
            ),
            container,
          ),
        );
        await tester.pump();
        final before = tester.widget<Image>(find.byType(Image)).key;

        // What `backOnline` and a session boundary do. The key has to change:
        // nothing re-resolves a settled ImageStream, so an image that failed while
        // offline would otherwise stay a fallback for the rest of the session.
        container.read(mediaReloadProvider.notifier).reload();
        await tester.pump();

        final after = tester.widget<Image>(find.byType(Image)).key;
        expect(after, isNot(before));
        // The URL itself is untouched — re-signing it is the backend's business,
        // and changing it here would invalidate the signature.
        expect(_resolvedUrl(tester), 'https://bucket.example/a.jpg');
      });
    });
  });

  group('UserAvatar', () {
    testWidgets('renders the fallback and fetches nothing without a picture', (
      tester,
    ) async {
      await _recordingNetwork(overrides, () async {
        await tester.pumpWidget(
          _host(
            const UserAvatar(imageUrl: null, radius: 20, fallback: Text('AB')),
            container,
          ),
        );
        await tester.pump();

        expect(find.text('AB'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        expect(overrides.requestedUrls, isEmpty);
      });
    });

    testWidgets('a replaced picture is a new URL, so it reloads by itself', (
      tester,
    ) async {
      await _recordingNetwork(overrides, () async {
        // The point of the backend writing a fresh object key per upload: the
        // widget's inputs genuinely change and it reloads on its own. Nothing
        // evicts a cache any more, because there is no longer a URL that stays
        // identical across a replacement.
        Widget avatarFor(String url) => _host(
          UserAvatar(imageUrl: url, radius: 20, fallback: const Text('AB')),
          container,
        );

        await tester.pumpWidget(avatarFor('https://bucket.example/first.png'));
        await tester.pump();
        expect(_resolvedUrl(tester), 'https://bucket.example/first.png');

        await tester.pumpWidget(avatarFor('https://bucket.example/second.png'));
        await tester.pump();
        expect(_resolvedUrl(tester), 'https://bucket.example/second.png');

        expect(overrides.requestedUrls.map((u) => u.path).toList(), [
          '/first.png',
          '/second.png',
        ]);
      });
    });
  });
}
