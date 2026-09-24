import 'package:flutter/material.dart';

/// Palette lifted from the Peerkola design prototype. Kept as plain constants
/// (rather than a [ThemeExtension]) since the palette is small and MVP-sized.
class AppColors {
  AppColors._();

  static const Color accentLight = Color(0xFF059669);
  static const Color accentDark = Color(0xFF34D399);

  static const Map<String, Color> channelColors = {
    'General': Color(0xFF6B7280),
    'Technology': Color(0xFF2563EB),
    'Outdoors': Color(0xFF16A34A),
    'Memes': Color(0xFFF59E0B),
    'Politics': Color(0xFFDC2626),
    'Local': Color(0xFF7C3AED),
  };

  static Color channelColor(String name) =>
      channelColors[name] ?? const Color(0xFF6B7280);

  /// Deterministic accent color for an avatar initial, derived from [seed]
  /// (typically a username) so the same user always gets the same color.
  static Color avatarColor(String seed) {
    const palette = [
      Color(0xFF2563EB),
      Color(0xFF16A34A),
      Color(0xFFF59E0B),
      Color(0xFFDC2626),
      Color(0xFF7C3AED),
      Color(0xFFEC4899),
      Color(0xFF059669),
    ];
    if (seed.isEmpty) return palette.first;
    final hash = seed.codeUnits.fold<int>(0, (acc, c) => acc + c);
    return palette[hash % palette.length];
  }
}
