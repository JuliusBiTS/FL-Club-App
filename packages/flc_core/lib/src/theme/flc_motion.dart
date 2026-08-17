import 'package:flutter/animation.dart';

/// Motion tokens — briefing §16.3. Always check
/// `MediaQuery.of(context).disableAnimations` (or the Riverpod equivalent)
/// before applying these and fall back to an immediate transition —
/// "respect reduce motion" is explicit in the brief, not a nice-to-have.
abstract final class FlcMotion {
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration sheet = Duration(milliseconds: 300);
  static const Curve standardCurve = Curves.easeOutCubic;

  /// The membership card sheet's own curve — briefing §16.3 calls for a
  /// spring, not easeOutCubic. Tune mass/stiffness/damping once the sheet
  /// is actually built and can be felt on a device.
  static const SpringDescription cardSheetSpring = SpringDescription(
    mass: 1,
    stiffness: 280,
    damping: 26,
  );
}
