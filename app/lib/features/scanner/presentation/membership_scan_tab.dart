import 'dart:async';

import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'scan_camera.dart';

import '../data/scan_pack_repository.dart';
import '../scanner_providers.dart';
import 'scan_result_overlay.dart';

enum _MembershipMode { qr, manual }

/// Membership mode — briefing §9.11/§13.4. Online only ("checked at
/// leisure at a desk", not a door queue), and the result screen must
/// never blur the three-tier trust model: a manual membership-number
/// lookup only ever gets tier 1 ("identification" — a username, not a
/// password), never the green "member confirmed" treatment a verified
/// rotating QR gets. See MembershipScanResultModel's doc comment.
class MembershipScanTab extends ConsumerStatefulWidget {
  const MembershipScanTab({required this.active, super.key});

  /// Only the visible tab may hold the camera.
  final bool active;

  @override
  ConsumerState<MembershipScanTab> createState() => _MembershipScanTabState();
}

class _MembershipScanTabState extends ConsumerState<MembershipScanTab> {
  _MembershipMode _mode = _MembershipMode.qr;
  final _numberController = TextEditingController();
  bool _busy = false;
  MembershipScanResultModel? _result;
  String? _error;

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(String payload) async {
    if (_busy) return;
    await _run(() async {
      final deviceId = await ref.read(deviceIdProvider).get();
      return ref.read(membershipScanRepositoryProvider).scanQr(payload: payload, deviceId: deviceId);
    });
  }

  Future<void> _lookupManual() async {
    final number = _numberController.text.trim();
    if (number.isEmpty) return;
    await _run(() async {
      final deviceId = await ref.read(deviceIdProvider).get();
      return ref.read(membershipScanRepositoryProvider).lookupManual(membershipNumber: number, deviceId: deviceId);
    });
  }

  Future<void> _run(Future<MembershipScanResultModel> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await call();
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = scanFunctionErrorMessage(e);
      });
    }
  }

  void _dismissResult() {
    _numberController.clear();
    setState(() {
      _result = null;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Scaffold(
          appBar: AppBar(title: const Text('Membership')),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(FlcSpace.md),
                child: SegmentedButton<_MembershipMode>(
                  segments: const <ButtonSegment<_MembershipMode>>[
                    ButtonSegment(value: _MembershipMode.qr, label: Text('Scan QR'), icon: Icon(Icons.qr_code_scanner)),
                    ButtonSegment(value: _MembershipMode.manual, label: Text('Manual'), icon: Icon(Icons.dialpad)),
                  ],
                  selected: <_MembershipMode>{_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
              ),
              if (_error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: FlcSpace.md),
                  padding: const EdgeInsets.all(FlcSpace.sm),
                  decoration: BoxDecoration(
                    color: FlcColors.scannerErrorBg,
                    borderRadius: BorderRadius.circular(FlcRadius.card),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Colors.white)),
                ),
              Expanded(child: _mode == _MembershipMode.qr ? _buildCamera() : _buildManual()),
            ],
          ),
        ),
        if (_result != null) Positioned.fill(child: _buildOverlay(_result!)),
      ],
    );
  }

  Widget _buildCamera() {
    if (!widget.active) return const SizedBox.expand();
    return ScanCamera(onCode: _onDetect);
  }

  Widget _buildManual() {
    return Padding(
      padding: const EdgeInsets.all(FlcSpace.md),
      child: Column(
        children: <Widget>[
          Text(
            'Barcode + number is identification only (tier 1) — never sufficient for a member discount on its own.',
            style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)),
          ),
          const SizedBox(height: FlcSpace.md),
          TextField(
            controller: _numberController,
            decoration: const InputDecoration(labelText: 'Membership number'),
            keyboardType: TextInputType.text,
            onSubmitted: (_) => _lookupManual(),
          ),
          const SizedBox(height: FlcSpace.md),
          FilledButton(onPressed: _busy ? null : _lookupManual, child: const Text('Look up')),
        ],
      ),
    );
  }

  /// The quick "who is this" card: type, number, since when, valid until.
  List<(String, String)> _memberFacts(MembershipScanResultModel r) {
    String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
    String date(String? iso, String pattern) {
      final d = iso == null ? null : DateTime.tryParse(iso);
      return d == null ? '' : DateFormat(pattern).format(d.toLocal());
    }

    final since = date(r.memberSince, 'MMM yyyy');
    final until = date(r.validTo, 'd MMM yyyy');
    return <(String, String)>[
      if (r.membershipKind != null) ('Membership', '${cap(r.membershipKind!)} member'),
      if (r.memberNumber != null && r.memberNumber!.isNotEmpty) ('Member no.', r.memberNumber!),
      if (since.isNotEmpty) ('Member since', since),
      ('Valid until', until.isEmpty ? 'No expiry date' : until),
    ];
  }

  Widget _buildOverlay(MembershipScanResultModel r) {
    if (r.result == 'valid' && r.authenticated) {
      return ScanResultOverlay.valid(
        title: r.fullName ?? 'Member',
        subtitle: 'Verified member',
        facts: _memberFacts(r),
        photoUrl: r.photoSignedUrl,
        onDismiss: _dismissResult,
      );
    }
    if (r.result == 'valid' && !r.authenticated) {
      return ScanResultOverlay.warning(
        title: r.fullName ?? 'Member',
        subtitle: 'Identified, not verified',
        detail: 'Check photo ID before honouring a member rate — this was a manual lookup, not a scanned QR.',
        facts: _memberFacts(r),
        photoUrl: r.photoSignedUrl,
        onDismiss: _dismissResult,
      );
    }
    final String message = switch (r.result) {
      'member_inactive' => 'Membership is not active',
      'member_expired' => 'Membership has expired',
      'not_found' => 'No member found',
      _ => "This doesn't look like a valid membership code",
    };
    return ScanResultOverlay.error(title: 'Not a member', subtitle: message, onDismiss: _dismissResult);
  }
}
