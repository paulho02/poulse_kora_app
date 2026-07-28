import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  /// Shared corner radius for buttons and cards. The design uses gently
  /// rounded rectangles, not Material 3's fully-rounded (stadium) button
  /// default.
  static const double radius = 12;

  static ThemeData light() => _build(_lightScheme());

  static ThemeData dark() => _build(_darkScheme());

  static ColorScheme _lightScheme() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.accentLight,
      brightness: Brightness.light,
    );
    // Drop the primary-into-surface tint so surfaces stay neutral and green
    // reads as a deliberate accent rather than an overall wash.
    return base.copyWith(surfaceTint: Colors.transparent);
  }

  static ColorScheme _darkScheme() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.accentDark,
      brightness: Brightness.dark,
    );
    // `fromSeed` derives *every* neutral (surfaces, background, outlines) from
    // the green seed, which tints the whole dark UI green. Override the neutral
    // ramp with true greys and keep green only as the accent/primary. Killing
    // `surfaceTint` also stops M3 from re-blending green into elevated surfaces.
    return base.copyWith(
      surface: const Color(0xFF121212),
      onSurface: const Color(0xFFE7E7E7),
      onSurfaceVariant: const Color(0xFFB4B4B4),
      surfaceContainerLowest: const Color(0xFF0D0D0D),
      surfaceContainerLow: const Color(0xFF171717),
      surfaceContainer: const Color(0xFF1C1C1C),
      surfaceContainerHigh: const Color(0xFF242424),
      surfaceContainerHighest: const Color(0xFF2C2C2C),
      outline: const Color(0xFF4A4A4A),
      outlineVariant: const Color(0xFF2E2E2E),
      surfaceTint: Colors.transparent,
    );
  }

  static ThemeData _build(ColorScheme colorScheme) {
    final brightness = colorScheme.brightness;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: GoogleFonts.spaceGroteskTextTheme(
        ThemeData(brightness: brightness).textTheme,
      ),
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(clipBehavior: Clip.antiAlias, shape: shape),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: shape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: shape),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: shape),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: shape),
      ),
    );
  }
}
