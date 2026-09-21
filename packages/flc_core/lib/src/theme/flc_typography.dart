import 'package:flutter/widgets.dart';

/// Type scale — briefing §16.2. A serif for headlines, a clean sans for UI,
/// reading as editorial to match the club's journalistic character.
///
/// The families are `Source Serif 4` (headings) and `Inter` (UI/body) — the
/// brief's pre-approved free substitutes for the website's own typefaces,
/// both under the SIL Open Font License, so cleared for embedding in the app
/// (see docs/OPEN_QUESTIONS.md if the club later licenses its own). The font
/// FILES (weights 400, 600, 700) and their licence texts live in
/// app/assets/fonts/ and admin/assets/fonts/, registered in each pubspec.yaml
/// `fonts:` section. If a family is ever missing, Flutter falls back to the
/// platform default font, so the app still runs.
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
