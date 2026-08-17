import 'package:flutter/widgets.dart';

/// Design tokens — briefing §16.1.
///
/// `brand` is sampled directly from the live site: the logo background
/// (frontlineclub.com/wp-content/uploads/2025/04/Frontline-Club-Logo.jpg)
/// and the site's own nav/button backgrounds all independently land on
/// the same #33460c dark olive — not the red originally guessed here
/// before anyone had checked. See docs/OPEN_QUESTIONS.md for anything
/// in this palette still unconfirmed.
abstract final class FlcColors {
  static const Color brand = Color(0xFF33460C);

  static const Color ink = Color(0xFF111214);
  static const Color graphite = Color(0xFF3A3D42);
  static const Color slate = Color(0xFF6B7076);

  static const Color paper = Color(0xFFFAF9F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1A1C1F);
  static const Color line = Color(0xFFE3E1DD);

  static const Color success = Color(0xFF1B7F4C);
  static const Color warning = Color(0xFFB8860B);
  static const Color error = Color(0xFFB3261E);

  // The membership card and every scanner result screen are always
  // dark-surfaced regardless of theme (§16.1) — read in dim rooms, and a
  // white flash in a darkened Forum is genuinely unpleasant.
  static const Color scannerValidBg = Color(0xFF0E3B24); // success flash background
  static const Color scannerWarningBg = Color(0xFF4A3B0A); // already-checked-in flash background
  static const Color scannerErrorBg = Color(0xFF4A1512); // invalid/refused flash background
}
