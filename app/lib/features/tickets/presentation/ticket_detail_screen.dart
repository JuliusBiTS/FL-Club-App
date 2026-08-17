import 'dart:async';

import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/platform/secure_screen.dart';
import '../tickets_providers.dart';

/// Briefing §9.4. Live 30s-rotating HMAC-signed QR, entirely offline once
/// ticket_secret is cached (§13.3) — a door with dead Wi-Fi doesn't stop a
/// ticket holder getting in, only stops the *staff* scanner verifying
/// (that's the `event_scan_key` half of the same scheme, downloaded ahead
/// of time via get-scan-pack, M5 scope). FLAG_SECURE for as long as this
/// screen is on top — a code that can be screenshotted and forwarded
/// defeats the entire point of rotating it.
class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({required this.ticket, super.key});

  final TicketModel ticket;

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  Timer? _tick;
  int? _lastCounter;
  String? _payload;
  String? _secret;
  bool _loadingSecret = true;

  @override
  void initState() {
    super.initState();
    unawaited(SecureScreen.enable());
    if (widget.ticket.isValid) {
      unawaited(_loadSecretAndStartRotating());
    } else {
      _loadingSecret = false;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(SecureScreen.disable());
    super.dispose();
  }

  Future<void> _loadSecretAndStartRotating() async {
    final secret = await ref.read(ticketsRepositoryProvider).getTicketSecret(widget.ticket.id);
    if (!mounted) return;
    setState(() {
      _secret = secret;
      _loadingSecret = false;
    });
    if (secret == null) return;

    _regeneratePayload();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _regeneratePayload());
  }

  void _regeneratePayload() {
    final counter = currentCounter();
    if (counter == _lastCounter) return;
    _lastCounter = counter;
    final secretBytes = base64UrlDecodeString(_secret!);
    final payload = currentTicketPayload(secretBytes, widget.ticket.id);
    if (mounted) setState(() => _payload = payload);
  }

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    final dateFormat = DateFormat('EEE d MMM yyyy, HH:mm');

    return Scaffold(
      backgroundColor: FlcColors.ink,
      appBar: AppBar(
        backgroundColor: FlcColors.ink,
        foregroundColor: Colors.white,
        title: Text(ticket.eventTitle, style: const TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FlcSpace.lg),
          child: Column(
            children: <Widget>[
              Text(
                dateFormat.format(ticket.eventStartsAt),
                style: FlcTextStyles.body.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FlcSpace.xs),
              Text(
                ticket.venueDisplay,
                style: FlcTextStyles.body.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FlcSpace.lg),
              _QrArea(ticket: ticket, loading: _loadingSecret, payload: _payload, hasSecret: _secret != null),
              const SizedBox(height: FlcSpace.md),
              Text(
                ticket.code,
                style: FlcTextStyles.h3.copyWith(color: Colors.white, letterSpacing: 2),
              ),
              const SizedBox(height: FlcSpace.xs),
              Text(
                'Show this at the door — no need to open the app in advance',
                style: FlcTextStyles.bodySmall.copyWith(color: Colors.white54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FlcSpace.lg),
              _DetailsCard(ticket: ticket),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrArea extends StatelessWidget {
  const _QrArea({required this.ticket, required this.loading, required this.payload, required this.hasSecret});

  final TicketModel ticket;
  final bool loading;
  final String? payload;
  final bool hasSecret;

  @override
  Widget build(BuildContext context) {
    const size = 240.0;

    if (!ticket.isValid) {
      final String label = switch (ticket.status) {
        'redeemed' => 'Already used',
        'refunded' => 'Refunded',
        'cancelled' => 'Cancelled',
        _ => 'No longer valid',
      };
      return _boxed(
        size,
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.check_circle_outline, size: 48, color: FlcColors.slate),
            const SizedBox(height: FlcSpace.sm),
            Text(label, style: FlcTextStyles.body.copyWith(color: FlcColors.slate)),
          ],
        ),
      );
    }

    if (loading) {
      return _boxed(size, const CircularProgressIndicator());
    }

    if (!hasSecret) {
      return _boxed(
        size,
        Padding(
          padding: const EdgeInsets.all(FlcSpace.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.wifi_off, size: 32, color: FlcColors.slate),
              const SizedBox(height: FlcSpace.sm),
              Text(
                "This ticket hasn't synced to this device yet — connect to the internet once to load it.",
                textAlign: TextAlign.center,
                style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate),
              ),
            ],
          ),
        ),
      );
    }

    if (payload == null) {
      return _boxed(size, const CircularProgressIndicator());
    }

    return _boxed(size, QrImageView(data: payload!, size: size - 32, backgroundColor: Colors.white));
  }

  Widget _boxed(double size, Widget child) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(FlcRadius.card)),
        child: Center(child: child),
      );
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.ticket});

  final TicketModel ticket;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FlcSpace.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(FlcRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (ticket.ticketTypeName != null) _row('Ticket', ticket.ticketTypeName!),
          if (ticket.attendeeName != null) _row('Attendee', ticket.attendeeName!),
          if (ticket.orderReference != null) _row('Order', ticket.orderReference!),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: FlcSpace.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label, style: FlcTextStyles.bodySmall.copyWith(color: Colors.white54)),
            Text(value, style: FlcTextStyles.bodySmall.copyWith(color: Colors.white)),
          ],
        ),
      );
}
