import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/profile_provider.dart';
import 'presentation/membership_card_sheet.dart';

/// The persistent handle above the bottom nav bar — briefing §9.6. "The
/// single most important interaction in the app" per the client: reachable
/// from anywhere in one gesture, opens in under 300ms, never needs a
/// network call. The actual card sheet (photo, barcode, PIN, rotating QR)
/// is M6 scope — this establishes the handle and its two states so the
/// shell is complete now.
///
/// Never render an empty/greyed-out card for a non-member (briefing §9.6)
/// — show the "Become a member" invitation instead, for guests too.
class MembershipCardHandle extends ConsumerWidget {
  const MembershipCardHandle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final bool isActiveMember = profile?.isActiveMember ?? false;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.xs),
        child: Material(
          color: FlcColors.ink,
          borderRadius: BorderRadius.circular(FlcRadius.membershipCard),
          child: InkWell(
            borderRadius: BorderRadius.circular(FlcRadius.membershipCard),
            onTap: () => isActiveMember
                ? _openMembershipCardSheet(context)
                : context.push('/you/become-a-member'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.badge_outlined, size: 18, color: isActiveMember ? scheme.primary : Colors.white70),
                  const SizedBox(width: FlcSpace.xs),
                  Text(
                    isActiveMember ? 'Membership Card' : 'Become a member',
                    style: FlcTextStyles.bodySmall.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: FlcSpace.xs),
                  const Icon(Icons.keyboard_arrow_up, size: 18, color: Colors.white70),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openMembershipCardSheet(BuildContext context) {
    // FLAG_SECURE, forced max brightness, and the rotating QR's lifecycle
    // all live inside MembershipCardSheet itself (tied to its own
    // initState/dispose) rather than here, so they're guaranteed to be
    // re-armed correctly however this sheet gets dismissed (swipe, back
    // gesture, tap-outside — not just a single "close" button).
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: FlcColors.ink,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FlcRadius.membershipCard)),
      ),
      builder: (context) => const MembershipCardSheet(),
    );
  }
}
