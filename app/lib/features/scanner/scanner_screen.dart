import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/membership_handle_visibility.dart';
import 'presentation/door_scan_tab.dart';
import 'presentation/membership_scan_tab.dart';

enum _ScanMode { door, membership }

/// Staff scanner — briefing §9.11. Door mode (tickets, offline-capable via
/// a downloaded scan pack) and Membership mode (online, photo comparison).
/// Route access is also re-verified server-side on every call — see
/// supabase/functions/verify-scan and get-scan-pack; this screen-level
/// gate (staff/admin only, see app_router.dart) is UX only.
///
/// The mode toggle sits above both tabs' own AppBars rather than as a
/// second bottom nav bar (this screen already lives inside the shell's
/// own bottom nav, see app_shell.dart) — one nav bar on screen at a time.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  _ScanMode _mode = _ScanMode.door;

  @override
  void initState() {
    super.initState();
    // Same overlap this fixes for the event detail buy bar (M3) — a
    // full-screen camera view with its own black AppBar has no business
    // sharing space with the floating membership handle. Deferred a
    // frame since mutating provider state during a still-building
    // widget tree (this screen's own initial build included) is unsafe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(showMembershipHandleProvider.notifier).state = false;
    });
  }

  @override
  void dispose() {
    ref.read(showMembershipHandleProvider.notifier).state = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(FlcSpace.sm),
              child: SegmentedButton<_ScanMode>(
                segments: const <ButtonSegment<_ScanMode>>[
                  ButtonSegment(value: _ScanMode.door, label: Text('Door'), icon: Icon(Icons.confirmation_number_outlined)),
                  ButtonSegment(value: _ScanMode.membership, label: Text('Membership'), icon: Icon(Icons.badge_outlined)),
                ],
                selected: <_ScanMode>{_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _mode.index,
              children: const <Widget>[DoorScanTab(), MembershipScanTab()],
            ),
          ),
        ],
      ),
    );
  }
}
