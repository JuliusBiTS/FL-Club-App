import 'package:flutter/widgets.dart';

/// Type scale — briefing §16.2. A serif for headlines, a clean sans for UI,
/// reading as editorial to match the club's journalistic character.
///
/// Font family names below assume `Source Serif 4` (headings) and `Inter`
/// (UI/body) — the brief's pre-approved free substitutes if the site's own
/// typefaces turn out not to be licensed for app embedding [CONFIRM], see
/// docs/OPEN_QUESTIONS.md. Font FILES are not bundled in this scaffold: add
/// the .ttf/.otf files under app/assets/fonts/ (and admin/assets/fonts/)
/// and register them in each app's pubspec.yaml `fonts:` section. Until
/// then Flutter silently falls back to the platform default font, so the
/// app still runs — it just won't look like itself yet.
abstract final class FlcFontFamily {
  static const String serif = 'Source Serif 4';
  static const String sans = 'Inter';
}

abstract final class FlcTextStyles {
  static const TextStyle display = TextStyle(
    fontFamily: FlcFontFamily.serif,
    fontSize: 32,
    height: 38 / 32,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle h1 = TextStyle(
    fontFamily: FlcFontFamily.serif,
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle h2 = TextStyle(
    fontFamily: FlcFontFamily.serif,
    fontSize: 21,
    height: 28 / 21,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle h3 = TextStyle(
    fontFamily: FlcFontFamily.sans,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle body = TextStyle(
    fontFamily: FlcFontFamily.sans,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle bodySmall = TextStyle(
    fontFamily: FlcFontFamily.sans,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle caption = TextStyle(
    fontFamily: FlcFontFamily.sans,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle overline = TextStyle(
    fontFamily: FlcFontFamily.sans,
    fontSize: 11,
    height: 16 / 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
  );
}
