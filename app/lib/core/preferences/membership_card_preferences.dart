import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The one on-device preference the membership card has: "always show it as
/// a small dot" rather than the full pill/card, for anyone who finds the
/// full version gets in the way. Nothing sensitive — plain SharedPreferences
/// is the right tool, unlike the ticket/membership secrets store.
class MembershipCardPreferences {
  MembershipCardPreferences(this._prefs);

  final SharedPreferences _prefs;

  static const String _alwaysDotKey = 'membership_card_always_dot';

  bool get alwaysDot => _prefs.getBool(_alwaysDotKey) ?? true;

  Future<void> setAlwaysDot(bool value) => _prefs.setBool(_alwaysDotKey, value);
}

/// Overridden in main.dart once SharedPreferences.getInstance() resolves —
/// same pattern as podcastAudioHandlerProvider.
final Provider<MembershipCardPreferences> membershipCardPreferencesProvider = Provider<MembershipCardPreferences>((ref) {
  throw UnimplementedError('membershipCardPreferencesProvider must be overridden in main.dart');
});

/// The live, settable value — seeded from the stored preference, updated (and
/// persisted) via [setAlwaysShowDot].
final StateProvider<bool> alwaysShowDotProvider = StateProvider<bool>((ref) {
  return ref.watch(membershipCardPreferencesProvider).alwaysDot;
});

void setAlwaysShowDot(WidgetRef ref, bool value) {
  ref.read(alwaysShowDotProvider.notifier).state = value;
  unawaited(ref.read(membershipCardPreferencesProvider).setAlwaysDot(value));
}
