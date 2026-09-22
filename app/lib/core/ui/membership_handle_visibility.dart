import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Claimed by a screen that needs the *entire* strip AppShell draws the
/// membership handle in — a full-width bottom bar of its own with nowhere
/// left for even a small dot (the event detail screen's "Get tickets" bar,
/// the article screen's "Read on the website" button, the scanner screen).
/// These are all screens pushed onto the Navigator (not shell-branch tabs
/// kept alive in an IndexedStack), so a screen claims this in initState and
/// MUST release it in dispose — that lifecycle is real for a pushed route,
/// which is what makes the plain imperative flag safe to use here.
///
/// This is deliberately NOT used for the Listen & Watch tab's mini-player —
/// see currentMediaItemProvider (podcast_providers.dart) and AppShell: that
/// conflict is instead derived reactively from the shell's current tab index
/// + whether something is loaded, precisely because a shell branch is never
/// disposed on a tab switch, so an imperative claim there could get stuck
/// (this was the cause of the membership card "disappearing forever after
/// the first podcast play" bug — fixed by computing it instead of setting it).
final StateProvider<bool> showMembershipHandleProvider = StateProvider<bool>((ref) => true);

/// What AppShell actually draws, computed fresh on every build from the
/// signals above — never a stale flag.
enum MembershipHandleMode {
  /// The full pill (guests) or drag-to-reveal card (members).
  full,

  /// A small, fixed circular dot — still one tap from the full card, out of
  /// the way of a screen that wants the space (the Listen tab's mini-player)
  /// or because the person has chosen to always keep it this small.
  dot,

  /// Nothing at all — only when a pushed screen has claimed the whole strip.
  hidden,
}
