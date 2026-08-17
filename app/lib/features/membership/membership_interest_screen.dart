import 'package:flutter/material.dart';

import '../../core/widgets/placeholder_screen.dart';

/// "Become a member" flow — briefing §9.7. Writes a membership_applications
/// row via the membership-apply Edge Function, then opens the device email
/// client via a prefilled mailto:. The app never sells membership.
class MembershipInterestScreen extends StatelessWidget {
  const MembershipInterestScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(title: 'Become a member', milestone: 'M6');
}
