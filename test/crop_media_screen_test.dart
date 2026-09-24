import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peerkola/l10n/generated/app_localizations.dart';
import 'package:peerkola/src/core/media/post_media_format.dart';
import 'package:peerkola/src/core/media/presentation/crop_media_screen.dart';

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

Widget _host(ui.Image image, void Function(CropResult?) onResult) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          onResult(
            await Navigator.of(context).push<CropResult>(
              MaterialPageRoute(
                builder: (_) => CropMediaScreen(
                  image: image,
                  aspects: const [
                    CropAspect(
                      ratio: kPostMediaPortraitRatio,
                      label: 'Upright',
                      icon: Icons.crop_portrait,
                    ),
                    CropAspect(
                      ratio: kPostMediaLandscapeRatio,
                      label: 'Wide',
                      icon: Icons.crop_landscape,
                    ),
                  ],
                  outputLongestSide: kPostCropLongestSide,
                  title: 'Crop photo',
                  hint: 'Drag to reposition',
                ),
              ),
            ),
          );
        },
        child: const Text('open'),
      ),
    ),
  );
}

Future<CropResult?> _cropWith(WidgetTester tester, {String? tapShape}) async {
  // `runAsync` throughout: decoding and rasterising go through the engine's
  // real task runner, which the fake-async zone `testWidgets` normally runs in
  // never advances — awaiting either one there hangs instead of failing.
  final image = (await tester.runAsync(() => _redImage(800, 600)))!;
  addTearDown(image.dispose);

  CropResult? result;
  var returned = false;
  await tester.pumpWidget(
    _host(image, (r) {
      result = r;
      returned = true;
    }),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  if (tapShape != null) {
    await tester.tap(find.text(tapShape));
    await tester.pumpAndSettle();
  }

  await tester.tap(find.text('Save'));
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await _pumpUntil(tester, () => returned);
  return result;
}

void main() {
  testWidgets('the default shape produces a portrait image at 4:5', (
    tester,
  ) async {
    final result = await _cropWith(tester);

    expect(result, isNotNull, reason: 'Save must pop the rendered crop');
    expect(result!.width, 1024);
    expect(result.height, kPostCropLongestSide);
    // The backend validates this ratio and rejects anything outside 2% of it,
    // so a drift here is a rejected upload, not a slightly odd-looking post.
    expect(result.aspectRatio / kPostMediaPortraitRatio - 1, closeTo(0, 0.02));
  });

  testWidgets('switching to the wide shape changes what is produced', (
    tester,
  ) async {
    final result = await _cropWith(tester, tapShape: 'Wide');

    expect(result, isNotNull);
    expect(result!.width, kPostCropLongestSide);
    expect(result.height, 960);
    expect(result.aspectRatio / kPostMediaLandscapeRatio - 1, closeTo(0, 0.02));
  });

  testWidgets('the crop is a real PNG, whatever the picker handed over', (
    tester,
  ) async {
    // The upload declares `image/png`, so the bytes have to actually be one —
    // that is the whole point of re-encoding here rather than forwarding what
    // image_picker returned, which differs per platform.
    final result = await _cropWith(tester);

    expect(
      result!.bytes.sublist(0, 8),
      orderedEquals([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    );
  });

  testWidgets('cancelling returns nothing', (tester) async {
    final image = (await tester.runAsync(() => _redImage(400, 400)))!;
    addTearDown(image.dispose);

    CropResult? result;
    var returned = false;
    await tester.pumpWidget(
      _host(image, (r) {
        result = r;
        returned = true;
      }),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(result, isNull);
  });
}
