import 'package:flutter/material.dart';

import '../../core/widgets/placeholder_screen.dart';

/// Loyalty progress + ledger — briefing §9.5, §10. One point per event per
/// person; the ledger view groups by event, never by ticket.
class LoyaltyScreen extends StatelessWidget {
  const LoyaltyScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(title: 'Loyalty', milestone: 'M7');
}
