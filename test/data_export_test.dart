import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/core/cache/json_cache.dart';
import 'package:peerkola/src/core/files/file_delivery.dart';
import 'package:peerkola/src/core/files/file_delivery_provider.dart';
import 'package:peerkola/src/features/profile/data/data_export.dart';
import 'package:peerkola/src/features/profile/application/profile_providers.dart';
import 'package:peerkola/src/features/profile/data/profile_repository.dart';
import 'package:peerkola/src/features/profile/presentation/data_export_tile.dart';

/// Settings → Download my data (GDPR Art. 15 / Art. 20).
///
/// The archive itself is the backend's business and is tested there. What has to
/// hold on this side is narrower and easy to get wrong silently: the bytes the
/// server sent are the bytes handed on unaltered, under the name the *server*
/// chose (it carries the export's date), and a refusal is reported rather than
/// swallowed - a download that quietly does nothing looks identical to one that
/// worked, since nothing in the app changes either way.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('the downloaded bytes are delivered under the server filename', (
    tester,
  ) async {
    final harness = await _pumpTile(tester);
    await tester.tap(find.text(l10n.settingsExportData));
    await tester.pumpAndSettle();

    expect(harness.delivered!.filename, 'peerkola-export-2026-09-16.zip');
    expect(harness.delivered!.bytes, _archiveBytes);
    expect(harness.delivered!.mimeType, 'application/zip');
    expect(find.text(l10n.settingsExportDataDone), findsOneWidget);
  });

  testWidgets('a header-less response still produces a usable name', (
    tester,
  ) async {
    final harness = await _pumpTile(tester);
    harness.backend.contentDisposition = null;
    await tester.tap(find.text(l10n.settingsExportData));
    await tester.pumpAndSettle();

    expect(harness.delivered!.filename, DataExport.fallbackFilename);
  });

  testWidgets('a dismissed share sheet claims nothing', (tester) async {
    // Nothing was saved, and the person is who decided that. A "ready" snackbar
    // here would be the app telling them they have a file they do not have.
    final harness = await _pumpTile(tester, delivery: FileDelivery.dismissed);
    await tester.tap(find.text(l10n.settingsExportData));
    await tester.pumpAndSettle();

    expect(harness.delivered, isNotNull);
    expect(find.text(l10n.settingsExportDataDone), findsNothing);
  });

  testWidgets('the daily budget gets its own sentence, not "N seconds"', (
    tester,
  ) async {
    // The shared `rate_limited` copy counts seconds, which is right for the
    // posting budget and absurd for one measured in days.
    final harness = await _pumpTile(tester);
    harness.backend.status = 429;
    await tester.tap(find.text(l10n.settingsExportData));
    await tester.pumpAndSettle();

    expect(find.text(l10n.settingsExportDataRateLimited), findsOneWidget);
    expect(harness.delivered, isNull);
  });

  testWidgets('the row cannot start a second download while one runs', (
    tester,
  ) async {
    final harness = await _pumpTile(tester);
    harness.backend.hold = true;
    await tester.tap(find.text(l10n.settingsExportData));
    await tester.pump();

    expect(find.text(l10n.settingsExportDataRunning), findsOneWidget);
    await tester.tap(find.text(l10n.settingsExportData));
    await tester.pump();

    harness.backend.release();
    await tester.pumpAndSettle();
    expect(harness.backend.requests, 1);
  });
}

final _archiveBytes = Uint8List.fromList([
  // A ZIP's local file header. Not a real archive - the point is that whatever
  // arrives is passed through untouched, and a recognisable prefix makes a
  // failure here readable.
  0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00,
]);

class _Delivered {
  _Delivered(this.filename, this.bytes, this.mimeType);

  final String filename;
  final Uint8List bytes;
  final String mimeType;
}

class _Harness {
  _Harness(this.backend);

  final _FakeBackend backend;
  _Delivered? delivered;
}

Future<_Harness> _pumpTile(
  WidgetTester tester, {
  FileDelivery delivery = FileDelivery.handedOff,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final backend = _FakeBackend();
  final harness = _Harness(backend);
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
  dio.httpClientAdapter = backend;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(
          ProfileRepository(dio, JsonCache(prefs)),
        ),
        fileDeliveryProvider.overrideWithValue(({
          required String filename,
          required Uint8List bytes,
          required String mimeType,
          Rect? shareOrigin,
        }) async {
          harness.delivered = _Delivered(filename, bytes, mimeType);
          return delivery;
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: DataExportTile()),
      ),
    ),
  );
  return harness;
}

class _FakeBackend implements HttpClientAdapter {
  int status = 200;
  int requests = 0;
  String? contentDisposition =
      'attachment; filename="peerkola-export-2026-09-16.zip"';

  /// Keeps a request in flight so the "already running" state is observable.
  bool hold = false;
  Completer<void>? _held;

  void release() {
    hold = false;
    _held?.complete();
    _held = null;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path != '/users/me/export') {
      throw StateError('unexpected request: ${options.path}');
    }
    requests++;
    if (hold) {
      _held = Completer<void>();
      await _held!.future;
    }
    if (status != 200) {
      return ResponseBody.fromString(
        jsonEncode({
          'detail': {'error': 'rate_limited', 'retry_after': 86400},
        }),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromBytes(
      _archiveBytes,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/zip'],
        if (contentDisposition != null)
          'content-disposition': [contentDisposition!],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
