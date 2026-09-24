import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/core/media/image_content_type.dart';
import 'package:peerkola/src/features/auth/application/auth_providers.dart';
import 'package:peerkola/src/features/feedback/application/feedback_providers.dart';
import 'package:peerkola/src/features/feedback/data/feedback_repository.dart';
import 'package:peerkola/src/features/feedback/presentation/feedback_screen.dart';

/// Captures what `submit` actually puts on the wire.
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  FormData? lastFormData;
  var statusCode = 201;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    lastFormData = options.data as FormData?;
    return ResponseBody.fromString(
      '{"id": 1, "kind": "feedback", "created": "2026-01-01T00:00:00Z"}',
      statusCode,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

FeedbackRepository _repository(_CapturingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
  dio.httpClientAdapter = adapter;
  return FeedbackRepository(dio);
}

Map<String, String> _fields(FormData form) => {
  for (final e in form.fields) e.key: e.value,
};

/// Mounts the screen with a stub repository, so the form can be driven without
/// a backend. `loggedIn` is what the screen keys its anonymity rules off.
Future<_CapturingAdapter> _pumpScreen(
  WidgetTester tester, {
  required bool loggedIn,
}) async {
  final adapter = _CapturingAdapter();
  // Tall enough for the whole form to be laid out at once: a `ListView` only
  // builds elements for what is on screen, so at the default 800x600 the
  // consent box and the button below it simply do not exist to be found.
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedbackRepositoryProvider.overrideWithValue(_repository(adapter)),
        // The screen only reads token *presence*, so a plain override of the
        // resolved value is enough and keeps secure storage out of the test.
        authNotifierProvider.overrideWith(() => _StubAuthNotifier(loggedIn)),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FeedbackScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  group('sniffImageContentType', () {
    // The one upload path with no cropper in front of it, so the declared
    // content type comes from the bytes rather than from a re-encode.
    test('recognizes PNG, JPEG and WebP from their magic bytes', () {
      expect(
        sniffImageContentType(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1]),
        ),
        'image/png',
      );
      expect(
        sniffImageContentType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1])),
        'image/jpeg',
      );
      expect(
        sniffImageContentType(
          Uint8List.fromList([
            ...'RIFF'.codeUnits,
            0, 0, 0, 0, // file size, deliberately not matched
            ...'WEBP'.codeUnits,
          ]),
        ),
        'image/webp',
      );
    });

    test('rejects anything else, including a truncated header', () {
      // A HEIC the picker didn't convert is the real case: caught here with a
      // message rather than as a 400 after the whole file has been uploaded.
      expect(
        sniffImageContentType(
          Uint8List.fromList([0, 0, 0, 0x18, ...'ftypheic'.codeUnits]),
        ),
        isNull,
      );
      expect(sniffImageContentType(Uint8List.fromList([0x89, 0x50])), isNull);
      expect(sniffImageContentType(Uint8List(0)), isNull);
      // RIFF without WEBP is a WAV, not an image.
      expect(
        sniffImageContentType(
          Uint8List.fromList([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WAVE'.codeUnits]),
        ),
        isNull,
      );
    });
  });

  group('FeedbackRepository.submit', () {
    test('sends every field as multipart form data', () async {
      final adapter = _CapturingAdapter();

      await _repository(adapter).submit(
        kind: FeedbackKind.bug,
        message: 'The feed is empty',
        consent: true,
        isAnonymous: true,
        allowContact: false,
      );

      expect(adapter.lastRequest!.method, 'POST');
      expect(adapter.lastRequest!.path, '/feedback');
      final fields = _fields(adapter.lastFormData!);
      expect(fields['kind'], 'bug');
      expect(fields['message'], 'The feed is empty');
      expect(fields['consent'], 'true');
      expect(fields['is_anonymous'], 'true');
      expect(fields['allow_contact'], 'false');
      // No client-supplied timestamp: `user_agreed_data_saving_at` is stamped
      // from the server clock, which is the whole point of it as a record.
      expect(fields.keys, isNot(contains('user_agreed_data_saving_at')));
      expect(adapter.lastFormData!.files, isEmpty);
    });

    test('sends a rating only for the kind that has one', () async {
      // The backend rejects a rating on any other kind rather than dropping it,
      // so a stray one would turn a bug report into a 400.
      final adapter = _CapturingAdapter();
      final repo = _repository(adapter);

      await repo.submit(
        kind: FeedbackKind.feedback,
        message: 'nice',
        consent: true,
        isAnonymous: false,
        allowContact: false,
        rating: 4,
      );
      expect(_fields(adapter.lastFormData!)['rating'], '4');

      await repo.submit(
        kind: FeedbackKind.bug,
        message: 'broken',
        consent: true,
        isAnonymous: false,
        allowContact: false,
        rating: 4,
      );
      expect(_fields(adapter.lastFormData!).keys, isNot(contains('rating')));
    });

    test('attaches every file under the same repeated field', () async {
      // Repeated keys in a map collapse; the backend reads `files` as a list.
      final adapter = _CapturingAdapter();

      await _repository(adapter).submit(
        kind: FeedbackKind.bug,
        message: 'see attached',
        consent: true,
        isAnonymous: true,
        allowContact: false,
        attachments: [
          FeedbackAttachment(
            bytes: Uint8List.fromList([1]),
            filename: 'shot.png',
            contentType: 'image/png',
            isVideo: false,
          ),
          FeedbackAttachment(
            bytes: Uint8List.fromList([2]),
            filename: 'clip.mp4',
            contentType: 'video/mp4',
            isVideo: true,
          ),
        ],
      );

      final files = adapter.lastFormData!.files;
      expect(files.map((e) => e.key), ['files', 'files']);
      expect(files.map((e) => e.value.filename), ['shot.png', 'clip.mp4']);
    });
  });

  group('FeedbackScreen', () {
    testWidgets('signed out, anonymity is locked on and contact is not offered', (
      tester,
    ) async {
      // The screen has to work with no account (it is linked from the login
      // screen), and there is then neither an identity to withhold nor a
      // verified address to reply to.
      final adapter = await _pumpScreen(tester, loggedIn: false);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      final anonymousTile = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, l10n.feedbackAnonymousLabel),
      );
      expect(anonymousTile.value, isTrue);
      expect(anonymousTile.onChanged, isNull, reason: 'must not be togglable');
      expect(find.text(l10n.feedbackAllowContactLabel), findsNothing);
      expect(find.text(l10n.feedbackAnonymousSignedOutHint), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'cannot log in');
      await tester.tap(find.text(l10n.feedbackConsentLabel));
      await tester.pump();
      await tester.tap(find.text(l10n.feedbackSubmit));
      await tester.pumpAndSettle();

      expect(_fields(adapter.lastFormData!)['is_anonymous'], 'true');
      expect(_fields(adapter.lastFormData!)['allow_contact'], 'false');
    });

    testWidgets('signed in, the contact option appears only while identified', (
      tester,
    ) async {
      await _pumpScreen(tester, loggedIn: true);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // Not anonymous by default when there is an account behind it.
      expect(find.text(l10n.feedbackAllowContactLabel), findsOneWidget);

      await tester.tap(find.text(l10n.feedbackAnonymousLabel));
      await tester.pumpAndSettle();
      // There is nothing to contact an anonymous submission at, and the backend
      // refuses the combination outright.
      expect(find.text(l10n.feedbackAllowContactLabel), findsNothing);
    });

    testWidgets('nothing is sent without consent, and the reason is shown', (
      tester,
    ) async {
      final adapter = await _pumpScreen(tester, loggedIn: true);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.enterText(find.byType(TextField), 'something');
      await tester.tap(find.text(l10n.feedbackSubmit));
      await tester.pumpAndSettle();

      expect(adapter.lastRequest, isNull, reason: 'must not reach the network');
      // Said in place, not via a disabled button: a greyed-out control never
      // explains what is missing.
      expect(find.text(l10n.feedbackBlockerConsent), findsOneWidget);
    });

    testWidgets('an empty message is refused before the request', (tester) async {
      final adapter = await _pumpScreen(tester, loggedIn: true);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.tap(find.text(l10n.feedbackConsentLabel));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text(l10n.feedbackSubmit));
      await tester.pumpAndSettle();

      expect(adapter.lastRequest, isNull);
      expect(find.text(l10n.feedbackBlockerMessage), findsOneWidget);
    });

    testWidgets('the star rating shows only for plain feedback', (tester) async {
      await _pumpScreen(tester, loggedIn: true);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.text(l10n.feedbackRatingLabel), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, l10n.feedbackKindBug));
      await tester.pumpAndSettle();
      expect(find.text(l10n.feedbackRatingLabel), findsNothing);
    });

    testWidgets('switching away from feedback clears an already-set rating', (
      tester,
    ) async {
      // Otherwise a rating chosen first would ride along on a bug report and be
      // rejected by the backend, which refuses rather than drops it.
      final adapter = await _pumpScreen(tester, loggedIn: true);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.tap(find.byTooltip(l10n.feedbackRatingStars(4)));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, l10n.feedbackKindBug));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, l10n.feedbackKindFeedback));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.text(l10n.feedbackConsentLabel));
      await tester.pump();
      await tester.tap(find.text(l10n.feedbackSubmit));
      await tester.pumpAndSettle();

      expect(_fields(adapter.lastFormData!).keys, isNot(contains('rating')));
    });
  });
}

/// Stands in for the real notifier, which reads `flutter_secure_storage`.
class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._loggedIn);

  final bool _loggedIn;

  @override
  Future<bool> build() async => _loggedIn;
}
