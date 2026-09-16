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

  // Text fields had three looks before one theme owned them: Material's
  // unfilled underline, a 4dp `OutlineInputBorder` on the search fields that
  // asked for one, and `InputBorder.none` in the composer. The first two are
  // gone; the third is now an explicit `filled: false` opt-out at each site,
  // which only works while the theme is the thing setting `filled`.
  testWidgets('text fields are filled and share the app corner radius', (
    tester,
  ) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final input = theme.inputDecorationTheme;
      expect(input.filled, isTrue);

      final border = input.border;
      expect(border, isA<OutlineInputBorder>());
      expect(
        (border! as OutlineInputBorder).borderRadius,
        BorderRadius.circular(AppTheme.radius),
      );
      // Nothing drawn around a field until it is focused — the fill is what
      // gives it a silhouette.
      expect(border.borderSide, BorderSide.none);
    }
  });

  testWidgets('a focused field is outlined in the accent', (tester) async {
    final theme = AppTheme.light();
    final focused = theme.inputDecorationTheme.focusedBorder;
    expect(focused?.borderSide.color, theme.colorScheme.primary);
    expect(
      theme.inputDecorationTheme.focusedErrorBorder?.borderSide.color,
      theme.colorScheme.error,
    );
  });
}
