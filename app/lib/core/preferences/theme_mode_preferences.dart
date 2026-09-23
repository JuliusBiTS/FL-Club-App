import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light/dark/system, persisted — feedback: "add a toggle for light and
/// dark mode in the settings". Defaults to light (dark and "match device" are opt-in),
/// the club's own look.
class ThemeModePreferences {
  ThemeModePreferences(this._prefs);

  final SharedPreferences _prefs;

  static const String _themeModeKey = 'app_theme_mode';

  ThemeMode get themeMode => switch (_prefs.getString(_themeModeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light, // the club's default look; dark and system are opt-in
      };

  Future<void> setThemeMode(ThemeMode mode) => _prefs.setString(_themeModeKey, mode.name);
}

/// Overridden in main.dart once SharedPreferences.getInstance() resolves —
/// same pattern as membershipCardPreferencesProvider.
final Provider<ThemeModePreferences> themeModePreferencesProvider = Provider<ThemeModePreferences>((ref) {
  throw UnimplementedError('themeModePreferencesProvider must be overridden in main.dart');
});

/// The live, settable value — seeded from the stored preference, updated
/// (and persisted) via [setThemeMode].
final StateProvider<ThemeMode> themeModeProvider = StateProvider<ThemeMode>((ref) {
  return ref.watch(themeModePreferencesProvider).themeMode;
});

void setThemeMode(WidgetRef ref, ThemeMode mode) {
  ref.read(themeModeProvider.notifier).state = mode;
  unawaited(ref.read(themeModePreferencesProvider).setThemeMode(mode));
}
