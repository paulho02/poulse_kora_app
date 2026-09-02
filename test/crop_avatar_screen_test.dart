import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/l10n/generated/app_localizations.dart';
import 'package:poulse_kora_app/src/core/media/presentation/crop_media_screen.dart';
import 'package:poulse_kora_app/src/features/profile/presentation/crop_avatar_screen.dart';

/// A plain red bitmap, big enough that the crop has something to sample.
Future<ui.Image> _redImage(int width, int height) {
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 0xFF; // r
    pixels[i + 3] = 0xFF; // a
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Pump frames until [done], instead of `pumpAndSettle`.
///
/// Saving swaps the button's label for a `CircularProgressIndicator`, which
/// animates for as long as it is mounted — so `pumpAndSettle` would wait for a
/// quiet frame that never arrives and hang the test rather than fail it.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int maxFrames = 120,
}) async {
  for (var i = 0; i < maxFrames && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Hosts the screen behind a push, the way the real caller invokes it.
Widget _host(ui.Image image, void Function(Uint8List?) onResult) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          final result = await Navigator.of(context).push<CropResult>(
            MaterialPageRoute(builder: (_) => CropAvatarScreen(image: image)),
          );
          onResult(result?.bytes);
        },
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  testWidgets('saving produces a decodable 512px square PNG', (tester) async {
    // `runAsync` throughout: decoding and rasterising go through the engine's
    // real task runner, which the fake-async zone `testWidgets` normally runs in
    // never advances — awaiting either one there hangs instead of failing.
    final image = (await tester.runAsync(() => _redImage(800, 600)))!;
    addTearDown(image.dispose);

    Uint8List? bytes;
    var returned = false;
    await tester.pumpWidget(
      _host(image, (b) {
        bytes = b;
        returned = true;
      }),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Crop picture'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pump();
    // Let the real rasterisation actually run, then drive the frames that
    // deliver its result back into the widget tree.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await _pumpUntil(tester, () => returned);

    expect(bytes, isNotNull, reason: 'Save must pop the rendered bytes');
    // The upload declares `image/png`, so the bytes have to actually be one
    // whatever format the user picked — that is the whole point of re-encoding
    // here rather than forwarding what the picker returned.
    expect(
      bytes!.sublist(0, 8),
      orderedEquals([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    );

    final decoded = (await tester.runAsync(() => decodeImageFromList(bytes!)))!;
    addTearDown(decoded.dispose);
    // Square regardless of the 4:3 source, so the avatar is never stretched.
    expect(decoded.width, 512);
    expect(decoded.height, 512);
  });

  testWidgets('cancelling returns nothing', (tester) async {
    final image = (await tester.runAsync(() => _redImage(400, 400)))!;
    addTearDown(image.dispose);

    Uint8List? bytes;
    var returned = false;
    await tester.pumpWidget(
      _host(image, (b) {
        bytes = b;
        returned = true;
      }),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(bytes, isNull);
  });
}
