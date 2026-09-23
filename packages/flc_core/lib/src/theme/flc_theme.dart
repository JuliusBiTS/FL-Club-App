import 'package:flutter/material.dart';

import 'flc_colors.dart';
import 'flc_spacing.dart';
import 'flc_typography.dart';

/// Material 3 theme built from the FLC design tokens. Both light and dark
/// are required (briefing §16.1) and should follow the system setting by
/// default — wire `ThemeMode.system` (or the You-tab override, §9.10) at
/// the MaterialApp level in app/lib/main.dart, not here.
abstract final class FlcTheme {
  static ThemeData light() => _build(brightness: Brightness.light);
  static ThemeData dark() => _build(brightness: Brightness.dark);

  static ThemeData _build({required Brightness brightness}) {
    final bool isDark = brightness == Brightness.dark;

    final ColorScheme colorScheme = ColorScheme(
      brightness: brightness,
      primary: FlcColors.brand,
      onPrimary: Colors.white,
      secondary: isDark ? FlcColors.graphiteOnDark : FlcColors.graphite,
      onSecondary: Colors.white,
      // Deliberately NOT dark-mode-adjusted here: colorScheme.error also
      // backs the delete-account button's solid fill (white text on top),
      // and a brighter dark-mode error would need onError to flip too —
      // more moving parts than the one place that actually shows error as
      // plain text needs. See FlcColors.errorAccent for that instead.
      error: FlcColors.error,
      onError: Colors.white,
      surface: isDark ? FlcColors.surfaceDark : FlcColors.surface,
      onSurface: isDark ? FlcColors.paper : FlcColors.ink,
    );

    final TextTheme textTheme = const TextTheme(
      displayLarge: FlcTextStyles.display,
      headlineLarge: FlcTextStyles.h1,
      headlineMedium: FlcTextStyles.h2,
      headlineSmall: FlcTextStyles.h3,
      bodyLarge: FlcTextStyles.body,
      bodyMedium: FlcTextStyles.bodySmall,
      labelSmall: FlcTextStyles.caption,
      labelMedium: FlcTextStyles.overline,
    ).apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      // The base family for every style not set explicitly in the textTheme
      // below (buttons, chips, list tiles, dialogs, form labels…), so nothing
      // silently falls back to the phone's default font.
      fontFamily: FlcFontFamily.sans,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? FlcColors.surfaceDark : FlcColors.paper,
      textTheme: textTheme,
      // A 1px hairline reads better than a shadow on light backgrounds
      // (§16.3) — elevation is used sparingly throughout.
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlcRadius.card),
          side: BorderSide(color: isDark ? Colors.white12 : FlcColors.line),
        ),
        color: colorScheme.surface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(FlcRadius.input)),
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48), // 48dp touch target, §6 accessibility
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlcRadius.input)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(FlcRadius.sheet)),
        ),
      ),
      // Brand identity, "very prominent, throughout the app": every app bar
      // and the bottom nav are always FlcColors.brand with white content,
      // in both themes — not just a light/dark-adapted primary colour.
      appBarTheme: AppBarTheme(
        backgroundColor: FlcColors.brand,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: FlcTextStyles.h2.copyWith(color: Colors.white),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: FlcColors.brand,
        indicatorColor: Colors.white.withValues(alpha: 0.16),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(WidgetState.selected) ? Colors.white : Colors.white70),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => FlcTextStyles.caption.copyWith(
            color: states.contains(WidgetState.selected) ? Colors.white : Colors.white70,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
      dividerColor: isDark ? Colors.white12 : FlcColors.line,
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
