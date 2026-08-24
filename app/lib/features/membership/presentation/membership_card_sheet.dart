import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import 'membership_card_back.dart';

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

class _MembershipCardSheetState extends ConsumerState<MembershipCardSheet> with SingleTickerProviderStateMixin {
  Timer? _tick;
  int? _lastCounter;
  String? _payload;
  MemberCardModel? _card;
  String? _photoPath;
  bool _loading = true;
  String? _error;

  late final AnimationController _flipController = AnimationController(
    duration: const Duration(milliseconds: 500),
    vsync: this,
  );
  bool _showingBack = false;

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
    _flipController.dispose();
    unawaited(SecureScreen.disable());
    unawaited(SecureScreen.restoreBrightness());
    super.dispose();
  }

  void _toggleFlip() {
    setState(() => _showingBack = !_showingBack);
    if (_showingBack) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
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
    // Only the loaded, real-card state is flippable — nothing to show on
    // the back while loading or errored.
    final flippable = !_loading && _card != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FlcSpace.md, FlcSpace.sm, FlcSpace.md, FlcSpace.md),
        child: flippable
            ? GestureDetector(
                onTap: _toggleFlip,
                child: AnimatedBuilder(
                  animation: _flipController,
                  builder: (context, child) {
                    final angle = _flipController.value * math.pi;
                    final showBack = angle > math.pi / 2;
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0015)
                        ..rotateY(angle),
                      child: showBack
                          ? Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()..rotateY(math.pi),
                              child: const MembershipCardBack(),
                            )
                          : _buildBody(),
                    );
                  },
                ),
              )
            : _buildBody(),
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
        Align(
          alignment: Alignment.centerLeft,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(FlcRadius.input),
            child: Image.asset('assets/images/brand/frontline_logo.jpg', height: 32, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: FlcSpace.sm),
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
        const SizedBox(height: FlcSpace.md),
        _QrArea(payload: _payload),
        const SizedBox(height: FlcSpace.xxs),
        Text(
          'Rotates every 30s — this is what a scanner verifies',
          style: FlcTextStyles.caption.copyWith(color: Colors.white54),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: FlcSpace.md),
        if (card.membershipNumber != null) ...<Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: FlcSpace.xs, horizontal: FlcSpace.md),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(FlcRadius.card)),
            child: bw.BarcodeWidget(
              barcode: bw.Barcode.code128(),
              data: card.membershipNumber!,
              height: 40,
              drawText: true,
              style: const TextStyle(color: Colors.black, fontSize: 12),
            ),
          ),
          const SizedBox(height: FlcSpace.xs),
        ],
        if (card.membershipPin != null)
          Text(
            'PIN  ${card.membershipPin}',
            style: FlcTextStyles.bodySmall.copyWith(color: Colors.white70, letterSpacing: 2),
          ),
        const SizedBox(height: FlcSpace.sm),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.sync_alt, size: 14, color: Colors.white38),
            const SizedBox(width: FlcSpace.xxs),
            Text('Tap for loyalty stamps', style: FlcTextStyles.caption.copyWith(color: Colors.white38)),
          ],
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
    const size = 48.0;
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
    const size = 132.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(FlcRadius.card)),
      child: Center(
        child: payload == null
            ? const CircularProgressIndicator()
            : QrImageView(data: payload!, size: size - 20, backgroundColor: Colors.white),
      ),
    );
  }
}
