import 'package:flutter/material.dart';

import 'tokens.dart';

/// Gargosy's only theme in v1: v2 dark (spec §7). Segoe UI, like v2 on Windows.
ThemeData gargosyTheme() {
  const scheme = ColorScheme.dark(
    primary: GColors.primary,
    onPrimary: GColors.fg,
    secondary: GColors.secondary,
    tertiary: GColors.accent,
    error: GColors.danger,
    surface: GColors.bg,
    onSurface: GColors.fg,
  );
  final base = ThemeData(brightness: Brightness.dark, colorScheme: scheme, useMaterial3: true, fontFamily: 'Segoe UI');
  return base.copyWith(
    scaffoldBackgroundColor: GColors.bg,
    textTheme: base.textTheme.apply(bodyColor: GColors.fg, displayColor: GColors.fg),
    dialogTheme: const DialogThemeData(
      backgroundColor: GColors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(GRadius.xl))),
    ),
    // A bright fill on a dark track, thick enough to read across the room.
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: GColors.primaryHover,
      linearTrackColor: GColors.surfaceHover,
      linearMinHeight: 6,
      borderRadius: BorderRadius.all(Radius.circular(3)),
    ),
    focusColor: GColors.focus,
    hoverColor: GColors.surfaceHover,
    splashFactory: NoSplash.splashFactory,
  );
}
