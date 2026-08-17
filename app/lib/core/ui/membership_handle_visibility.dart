import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The membership card handle (briefing §9.6) is a persistent overlay
/// drawn by AppShell above every screen in the tab shell, at the exact
/// spot a screen-specific bottom action bar (e.g. the event detail
/// screen's "Get tickets" bar) also wants to occupy. Rather than have
/// screens render their own bottom bar UNDER the handle (where it gets
/// visually clipped), a screen that needs that space claims it by
/// flipping this to false while its own bar is showing, and MUST restore
/// it (typically in dispose()) — the handle is meant to be reachable from
/// anywhere, so hiding it should never outlive the screen that hid it.
final StateProvider<bool> showMembershipHandleProvider = StateProvider<bool>((ref) => true);
