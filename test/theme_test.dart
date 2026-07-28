import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/src/core/theme/app_theme.dart';

// These run as `testWidgets` (not plain `test`) so theme construction happens
// under the widget-test binding, which tolerates google_fonts' offline
// fallback the same way the app's widget test does.
void main() {
  int channel(double v) => (v * 255).round();

  testWidgets('dark surfaces are neutral grey, not tinted green', (
    tester,
  ) async {
    final scheme = AppTheme.dark().colorScheme;

    // A truly neutral grey has near-equal R/G/B channels. The bug we're
    // guarding against is `ColorScheme.fromSeed(green)` bleeding green into
    // every surface, which shows up as G noticeably higher than R/B.
    final r = channel(scheme.surface.r);
    final g = channel(scheme.surface.g);
    final b = channel(scheme.surface.b);

    expect((r - g).abs(), lessThanOrEqualTo(4));
    expect((g - b).abs(), lessThanOrEqualTo(4));
  });

  testWidgets('accent/primary stays green in dark mode', (tester) async {
    final primary = AppTheme.dark().colorScheme.primary;
    // Green channel should dominate for the accent color.
    expect(channel(primary.g), greaterThan(channel(primary.r)));
    expect(channel(primary.g), greaterThan(channel(primary.b)));
  });

  testWidgets('buttons use a rounded rectangle, not a stadium shape', (
    tester,
  ) async {
    final shape = AppTheme.light().filledButtonTheme.style?.shape?.resolve({});
    expect(shape, isA<RoundedRectangleBorder>());
  });
}
