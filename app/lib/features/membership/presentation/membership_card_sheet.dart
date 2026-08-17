import 'dart:async';
import 'dart:io';

import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;

import '../../../core/platform/secure_screen.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../data/member_card_repository.dart';
import '../membership_providers.dart';

/// The membership card itself — briefing §9.6/§13.4, and the three-tier
/// trust model from DECISIONS.md:
///   1. Identification — barcode + number + PIN. A username, never a
///      password: convenience only (bar tab, reception).
///   2. Authentication — this screen's 30s-rotating HMAC QR, the only
///      thing verify-scan accepts as sufficient for a member price.
///   3. Verification of person — staff compare the photo to the holder.
/// All three tiers are on screen at once; nothing here claims to BE the
/// verification, it just supplies what each tier needs.
class MembershipCardSheet extends ConsumerStatefulWidget {
  const MembershipCardSheet({super.key});

  @override
  ConsumerState<MembershipCardSheet> createState() => _MembershipCardSheetState();
}

class _MembershipCardSheetState extends ConsumerState<MembershipCardSheet> {
  Timer? _tick;
  int? _lastCounter;
  String? _payload;
  MemberCardModel? _card;
  String? _photoPath;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(SecureScreen.enable());
    unawaited(SecureScreen.setMaxBrightness());
    unawaited(_load());
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(SecureScreen.disable());
    unawaited(SecureScreen.restoreBrightness());
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(memberCardRepositoryProvider);

    final cached = await repo.getCached();
    if (cached != null) {
      final photoPath = await repo.cachedPhotoPath();
      if (!mounted) return;
      setState(() {
        _card = cached;
        _photoPath = photoPath;
        _loading = false;
      });
      _startRotating();
    }

    try {
      final fresh = await repo.refresh();
      final photoPath = await repo.cachedPhotoPath();
      if (!mounted) return;
      setState(() {
        _card = fresh;
        _photoPath = photoPath;
        _loading = false;
        _error = null;
      });
      if (_tick == null) _startRotating();
    } catch (e) {
      if (!mounted) return;
      if (_card == null) {
        setState(() {
          _loading = false;
          _error = memberCardErrorMessage(e);
        });
      }
      // else: keep showing the cached card — offline rendering is the
      // whole point (briefing §9.6), a failed refresh isn't fatal.
    }
  }

  void _startRotating() {
    _regeneratePayload();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _regeneratePayload());
  }

  void _regeneratePayload() {
    final card = _card;
    final userId = ref.read(currentUserProvider)?.id;
    if (card == null || userId == null) return;
    final counter = currentCounter();
    if (counter == _lastCounter) return;
    _lastCounter = counter;
    final secretBytes = base64UrlDecodeString(card.memberSecret);
    final payload = currentMemberPayload(secretBytes, userId);
    if (mounted) setState(() => _payload = payload);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FlcSpace.lg, FlcSpace.md, FlcSpace.lg, FlcSpace.lg),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    final card = _card;
    if (card == null) {
      return SizedBox(
        height: 320,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(FlcSpace.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.error_outline, color: Colors.white70, size: 32),
                const SizedBox(height: FlcSpace.sm),
                Text(
                  _error ?? "Couldn't load your card.",
                  style: FlcTextStyles.body.copyWith(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final dateFormat = DateFormat('d MMM yyyy');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            _Photo(path: _photoPath),
            const SizedBox(width: FlcSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    card.fullName,
                    style: FlcTextStyles.h3.copyWith(color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (card.membershipKind != null) ...<Widget>[
                    const SizedBox(height: FlcSpace.xxs),
                    Text(
                      '${_kindLabel(card.membershipKind!)} member',
                      style: FlcTextStyles.bodySmall.copyWith(color: Colors.white70),
                    ),
                  ],
                  if (card.validTo != null) ...<Widget>[
                    const SizedBox(height: FlcSpace.xxs),
                    Text(
                      'Valid to ${dateFormat.format(card.validTo!)}',
                      style: FlcTextStyles.bodySmall.copyWith(color: Colors.white54),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: FlcSpace.lg),
        _QrArea(payload: _payload),
        const SizedBox(height: FlcSpace.xs),
        Text(
          'Rotates every 30s — this is what a scanner verifies',
          style: FlcTextStyles.bodySmall.copyWith(color: Colors.white54),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: FlcSpace.lg),
        if (card.membershipNumber != null) ...<Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: FlcSpace.sm),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(FlcRadius.card)),
            child: bw.BarcodeWidget(
              barcode: bw.Barcode.code128(),
              data: card.membershipNumber!,
              height: 56,
              drawText: true,
              style: const TextStyle(color: Colors.black, fontSize: 13),
            ),
          ),
          const SizedBox(height: FlcSpace.sm),
        ],
        if (card.membershipPin != null)
          Text(
            'PIN  ${card.membershipPin}',
            style: FlcTextStyles.body.copyWith(color: Colors.white70, letterSpacing: 2),
          ),
      ],
    );
  }

  String _kindLabel(String kind) => switch (kind) {
        'lifetime' => 'Lifetime',
        'honorary' => 'Honorary',
        _ => 'Full',
      };
}

class _Photo extends StatelessWidget {
  const _Photo({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    if (path == null) {
      return const CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.white24,
        child: Icon(Icons.person, color: Colors.white70),
      );
    }
    return CircleAvatar(radius: size / 2, backgroundImage: FileImage(File(path!)));
  }
}

class _QrArea extends StatelessWidget {
  const _QrArea({required this.payload});

  final String? payload;

  @override
  Widget build(BuildContext context) {
    const size = 200.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(FlcRadius.card)),
      child: Center(
        child: payload == null
            ? const CircularProgressIndicator()
            : QrImageView(data: payload!, size: size - 32, backgroundColor: Colors.white),
      ),
    );
  }
}
