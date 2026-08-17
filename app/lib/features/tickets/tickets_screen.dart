import 'package:flutter/material.dart';

import '../../core/widgets/placeholder_screen.dart';

/// My tickets — briefing §9.4. Rotating signed QR, FLAG_SECURE, offline
/// rendering from local secure storage. See
/// packages/flc_core/lib/src/crypto/ticket_crypto.dart for the code
/// generation this screen will drive.
class TicketsScreen extends StatelessWidget {
  const TicketsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(title: 'My tickets', milestone: 'M4');
}
