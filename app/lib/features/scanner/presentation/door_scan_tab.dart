import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/local_db/app_database_provider.dart';
import '../../events/presentation/events_feed_controller.dart';
import '../data/scan_pack_repository.dart';
import '../scanner_providers.dart';
import 'scan_result_overlay.dart';

/// Door mode — briefing §13.5. Pick an event, download its scan pack once,
/// then scan entirely offline for the rest of the door shift. Camera
/// pauses (not stops) while a result is on screen so the same code isn't
/// re-detected before staff dismisses it.
class DoorScanTab extends ConsumerStatefulWidget {
  const DoorScanTab({super.key});

  @override
  ConsumerState<DoorScanTab> createState() => _DoorScanTabState();
}

class _DoorScanTabState extends ConsumerState<DoorScanTab> {
  MobileScannerController? _controller;
  String? _eventId;
  String? _eventTitle;
  bool _busy = false;
  bool _loadingPack = false;
  String? _loadError;
  TicketScanResultModel? _result;
  int _pendingCount = 0;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    // Best-effort: a sync is also attempted after every scan (see
    // _trySync below), so this only matters for the case where staff
    // walk back into signal without scanning anything else for a while —
    // reconnecting shouldn't require an extra scan just to flush the
    // queue.
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(_trySync());
      }
    });
  }

  @override
  void dispose() {
    unawaited(_connectivitySub?.cancel());
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _selectEvent(EventModel event) async {
    setState(() {
      _loadingPack = true;
      _loadError = null;
    });
    try {
      await ref.read(scanPackRepositoryProvider).download(event.id);
      final controller = MobileScannerController();
      if (!mounted) {
        unawaited(controller.dispose());
        return;
      }
      setState(() {
        _controller = controller;
        _eventId = event.id;
        _eventTitle = event.title;
        _loadingPack = false;
      });
      await _refreshPendingCount();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPack = false;
        _loadError = scanFunctionErrorMessage(e);
      });
    }
  }

  Future<void> _refreshPendingCount() async {
    final eventId = _eventId;
    if (eventId == null) return;
    final pending = await ref.read(appDatabaseProvider).pendingScansFor(eventId);
    if (mounted) setState(() => _pendingCount = pending.length);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final eventId = _eventId;
    if (_busy || eventId == null || capture.barcodes.isEmpty) return;
    final payload = capture.barcodes.first.rawValue;
    if (payload == null) return;

    setState(() => _busy = true);
    final result = await ref.read(doorScanRepositoryProvider).scan(eventId: eventId, payload: payload);
    if (!mounted) return;
    setState(() => _result = result);
    unawaited(_trySync());
  }

  Future<void> _trySync() async {
    final eventId = _eventId;
    if (eventId == null) return;
    try {
      final deviceId = await ref.read(deviceIdProvider).get();
      await ref.read(doorScanRepositoryProvider).syncPending(eventId, deviceId);
    } catch (_) {
      // Offline, or the sync itself failed — scans stay queued, safe to
      // retry, so there's nothing to surface to staff mid-scan.
    }
    await _refreshPendingCount();
  }

  void _dismissResult() {
    setState(() {
      _result = null;
      _busy = false;
    });
  }

  void _switchEvent() {
    unawaited(_controller?.dispose());
    setState(() {
      _controller = null;
      _eventId = null;
      _eventTitle = null;
      _result = null;
      _pendingCount = 0;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final eventId = _eventId;

    if (eventId == null || controller == null) {
      return _EventPicker(loading: _loadingPack, error: _loadError, onSelect: _selectEvent);
    }

    return Stack(
      children: <Widget>[
        Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Switch event', onPressed: _switchEvent),
            title: Text(_eventTitle ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
            actions: <Widget>[
              IconButton(
                icon: _pendingCount > 0
                    ? Badge(label: Text('$_pendingCount'), child: const Icon(Icons.sync))
                    : const Icon(Icons.sync),
                tooltip: 'Sync now',
                onPressed: _trySync,
              ),
              IconButton(
                icon: const Icon(Icons.flash_on),
                tooltip: 'Torch',
                onPressed: () => controller.toggleTorch(),
              ),
            ],
          ),
          body: MobileScanner(controller: controller, onDetect: _onDetect),
        ),
        if (_result != null) Positioned.fill(child: _buildOverlay(_result!)),
      ],
    );
  }

  Widget _buildOverlay(TicketScanResultModel r) {
    switch (r.result) {
      case 'valid':
        return ScanResultOverlay.valid(
          title: 'Valid ticket',
          subtitle: r.attendeeName ?? r.ticketTypeName,
          onDismiss: _dismissResult,
        );
      case 'already_redeemed':
        return ScanResultOverlay.warning(
          title: 'Already used',
          subtitle: r.attendeeName,
          detail: 'This ticket was already scanned in',
          onDismiss: _dismissResult,
        );
      case 'ticket_refunded':
        return ScanResultOverlay.error(
          title: 'Refunded',
          subtitle: 'This ticket is no longer valid',
          onDismiss: _dismissResult,
        );
      case 'expired_code':
        return ScanResultOverlay.error(
          title: 'Code expired',
          subtitle: 'Ask them to reopen their ticket and rescan',
          onDismiss: _dismissResult,
        );
      case 'not_found':
        return ScanResultOverlay.error(
          title: 'Not found',
          subtitle: "This code isn't a ticket for this event",
          onDismiss: _dismissResult,
        );
      default:
        return ScanResultOverlay.error(
          title: 'Invalid code',
          subtitle: "This doesn't look like a valid ticket",
          onDismiss: _dismissResult,
        );
    }
  }
}

class _EventPicker extends ConsumerWidget {
  const _EventPicker({required this.loading, required this.error, required this.onSelect});

  final bool loading;
  final String? error;
  final ValueChanged<EventModel> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsFeedControllerProvider);
    final dateFormat = DateFormat('EEE d MMM, HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Scan — pick an event')),
      body: Column(
        children: <Widget>[
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FlcSpace.md),
              color: FlcColors.scannerErrorBg,
              child: Text(error!, style: const TextStyle(color: Colors.white)),
            ),
          Expanded(
            child: eventsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => const Center(child: Text("Couldn't load events.")),
              data: (events) {
                if (events.isEmpty) return const Center(child: Text('No events to scan for.'));
                return ListView.builder(
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return ListTile(
                      leading: const Icon(Icons.event_outlined),
                      title: Text(event.title),
                      subtitle: Text(dateFormat.format(event.startsAt)),
                      trailing: const Icon(Icons.download_outlined),
                      onTap: loading ? null : () => onSelect(event),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
