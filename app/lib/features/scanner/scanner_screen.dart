import 'package:flutter/material.dart';

import '../../core/widgets/placeholder_screen.dart';

/// Staff scanner — briefing §9.11. Door mode (tickets, offline-capable via
/// a downloaded scan pack) and Membership mode (online, photo comparison).
/// Route access is also re-verified server-side on every call — see
/// supabase/functions/verify-scan and get-scan-pack; this screen-level
/// gate (staff/admin only, see app_router.dart) is UX only.
class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(title: 'Scan', milestone: 'M5');
}
