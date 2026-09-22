import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/profile_provider.dart';
import '../../core/ui/membership_handle_visibility.dart';
import 'presentation/membership_card_sheet.dart';

/// A border + shadow every state of the handle shares — this, not a colour
/// change, is what gives it "contour" against the also-brand-olive app bar
/// and bottom nav it sits between, so it reads as its own floating object
/// rather than blending into either.
const BoxShadow _kHandleShadow = BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3));
final Border _kHandleBorder = Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.2);

/// The persistent handle above the bottom nav bar — briefing §9.6,
/// modelled on Waterstones' Plus card: "the single most important
/// interaction in the app," reachable from anywhere in one gesture. For an
/// active member this is a real drag-to-reveal — the card peeks up from
/// the handle as you drag, like Waterstones/Apple Wallet, not a button
/// that pops a disconnected sheet. A tap on the handle still works too
/// (accessibility, and plain habit). Guests have no card to peek at, so
/// they keep the simple tap-through pill straight to the sign-up flow —
/// briefing §9.6: never render an empty/greyed-out card for a non-member.
///
/// [mode] is computed by AppShell every build (see
/// core/ui/membership_handle_visibility.dart) — this widget only ever
/// renders whatever it's told, it never decides on its own to hide.
class MembershipCardHandle extends ConsumerWidget {
  const MembershipCardHandle({required this.activeTabIndex, required this.mode, super.key});

  /// AppShell's navigationShell.currentIndex — watched only so the card
  /// can auto-collapse the instant the user switches tabs mid-drag. Left
  /// open, a rotating QR + PIN would otherwise float over whatever screen
  /// they just switched to.
  final int activeTabIndex;

  final MembershipHandleMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (mode == MembershipHandleMode.hidden) return const SizedBox.shrink();

    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final bool isActiveMember = profile?.isActiveMember ?? false;

    if (mode == MembershipHandleMode.dot) {
      return Align(
        alignment: Alignment.bottomRight,
        child: _HandleDot(isActiveMember: isActiveMember),
      );
    }

    if (!isActiveMember) {
      return const Align(alignment: Alignment.bottomCenter, child: _GuestPill());
    }

    return _MemberCardRevealSheet(activeTabIndex: activeTabIndex);
  }
}

/// The minimised form — a small circle in the bottom-right corner, always
/// reachable, never overlapping a full-width bar (mini-player or a
/// screen's own bottom bar) the way the full pill/card would.
class _HandleDot extends StatelessWidget {
  const _HandleDot({required this.isActiveMember});

  final bool isActiveMember;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(right: FlcSpace.md, bottom: FlcSpace.sm),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: FlcColors.brand,
            shape: BoxShape.circle,
            border: _kHandleBorder,
            boxShadow: const <BoxShadow>[_kHandleShadow],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => isActiveMember ? MembershipCardSheet.showModal(context) : context.push('/you/become-a-member'),
              child: Icon(isActiveMember ? Icons.badge_outlined : Icons.person_add_alt_1_outlined, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuestPill extends StatelessWidget {
  const _GuestPill();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.xs),
        child: Container(
          decoration: BoxDecoration(
            color: FlcColors.brand,
            borderRadius: BorderRadius.circular(FlcRadius.membershipCard),
            border: _kHandleBorder,
            boxShadow: const <BoxShadow>[_kHandleShadow],
          ),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(FlcRadius.membershipCard),
            child: InkWell(
              borderRadius: BorderRadius.circular(FlcRadius.membershipCard),
              onTap: () => context.push('/you/become-a-member'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.badge_outlined, size: 18, color: Colors.white70),
                    const SizedBox(width: FlcSpace.xs),
                    Text('Become a member', style: FlcTextStyles.bodySmall.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(width: FlcSpace.xs),
                    const Icon(Icons.keyboard_arrow_up, size: 18, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Height of the collapsed "peek handle" strip — same visual weight as the
/// pill it replaces.
const double _kHandleHeight = 56;

class _MemberCardRevealSheet extends StatefulWidget {
  const _MemberCardRevealSheet({required this.activeTabIndex});

  final int activeTabIndex;

  @override
  State<_MemberCardRevealSheet> createState() => _MemberCardRevealSheetState();
}

class _MemberCardRevealSheetState extends State<_MemberCardRevealSheet> {
  final DraggableScrollableController _controller = DraggableScrollableController();

  // Recomputed every build (screen size doesn't change mid-session) so the
  // collapsed state matches the handle's real pixel height exactly rather
  // than an eyeballed fraction — see didUpdateWidget for why it's cached.
  double _collapsedSize = 0.1;
  // A genuine card, not a sheet that swallows the screen — Waterstones'
  // own Plus card tops out around a third of the display; this leaves
  // headroom for the photo/QR/barcode/PIN this card carries that theirs
  // doesn't (briefing's three-tier trust model), but stays a floating
  // card, not a takeover.
  static const double _expandedSize = 0.52;
  static const double _revealEpsilon = 0.01;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MemberCardRevealSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTabIndex != widget.activeTabIndex && _controller.isAttached) {
      _controller.animateTo(_collapsedSize, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _toggle() {
    if (!_controller.isAttached) return;
    final bool isRevealed = _controller.size > _collapsedSize + _revealEpsilon;
    _controller.animateTo(
      isRevealed ? _collapsedSize : _expandedSize,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double bottomInset = MediaQuery.paddingOf(context).bottom;
        _collapsedSize = ((_kHandleHeight + bottomInset) / constraints.maxHeight).clamp(0.04, 0.3);

        // DraggableScrollableSheet only invokes `builder` once, at mount —
        // it's passed as the static `child` of an internal
        // ValueListenableBuilder, so the widget it returns is cached and
        // reused across every drag/animation frame (only the wrapping
        // FractionallySizedBox's heightFactor changes). Without this
        // NotificationListener, isRevealed/the header icon/the conditional
        // MembershipCardSheet mount would be frozen at their initial
        // (collapsed) values forever, even though the sheet visibly
        // resizes. This is the same pattern Flutter's own docs use for a
        // persistent bottom sheet that needs to react to its own extent.
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: (notification) {
            setState(() {});
            return false;
          },
          child: DraggableScrollableSheet(
            controller: _controller,
            initialChildSize: _collapsedSize,
            minChildSize: _collapsedSize,
            maxChildSize: _expandedSize,
            snap: true,
            builder: (context, scrollController) {
              final bool isRevealed = _controller.isAttached && _controller.size > _collapsedSize + _revealEpsilon;
              // The DraggableScrollableSheet's own box is always full-width
              // and only resizable vertically — the horizontal margin here
              // (and rounding all four corners, not just the top) is what
              // makes this actually read as a floating card over the page
              // rather than a full-bleed sheet, matching Waterstones' Plus
              // card. The margin area stays transparent, so whatever's
              // behind (the current tab's content) shows through either
              // side, exactly like the reference.
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(FlcRadius.membershipCard),
                    border: _kHandleBorder,
                    boxShadow: const <BoxShadow>[_kHandleShadow],
                  ),
                  child: Material(
                    color: FlcColors.brand,
                    borderRadius: BorderRadius.circular(FlcRadius.membershipCard),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      controller: scrollController,
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          InkWell(
                            onTap: _toggle,
                            child: SizedBox(
                              height: _kHandleHeight,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  const Icon(Icons.badge_outlined, size: 18, color: Colors.white),
                                  const SizedBox(width: FlcSpace.xs),
                                  Text(
                                    'Membership Card',
                                    style: FlcTextStyles.bodySmall.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: FlcSpace.xs),
                                  Icon(
                                    isRevealed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                                    size: 18,
                                    color: Colors.white70,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Only actually mounted while revealed — this is what
                          // arms/disarms FLAG_SECURE, forced max brightness and
                          // the rotating-QR timer, via MembershipCardSheet's own
                          // initState/dispose (briefing §9.4/§9.6). Keeping that
                          // live for a card that isn't visibly on screen would
                          // force max brightness and block screenshots app-wide
                          // for as long as a member is signed in — not just
                          // while the card is actually showing.
                          if (isRevealed) const MembershipCardSheet() else SizedBox(height: bottomInset),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
