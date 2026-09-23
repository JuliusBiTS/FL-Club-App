import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;

import '../../../core/platform/secure_screen.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../data/member_card_repository.dart';
import '../membership_providers.dart';
import 'membership_card_back.dart';
import 'membership_card_wordmark.dart';

/// Photo and QR share this size — briefing feedback (2026-08-24): "photo
/// on the left of it in the same size" as the QR, side by side in the
/// scan panel rather than the QR alone with a small avatar up top.
const double _kIdBlockSize = 104;

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

  /// Opens the card as a standalone modal — used wherever there's no
  /// drag-to-reveal handle to peek it out of (the minimised dot, and the
  /// You tab's always-there entry point).
  static Future<void> showModal(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: FlcColors.brand,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(FlcRadius.sheet))),
      isScrollControlled: true,
      builder: (BuildContext context) => const MembershipCardSheet(),
    );
  }

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

  /// True specifically for get-member-card's 403 ("not an active member")
  /// — a real, expected state for a signed-in guest/staff account, not a
  /// broken card. Kept separate from _error so it gets its own friendly
  /// screen instead of a generic "couldn't load" message.
  bool _notAMember = false;

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

    // Bug fix: this used to run outside the try/catch below. Any exception
    // reading the cache — flutter_secure_storage genuinely can throw here,
    // e.g. after a reinstall invalidates its keystore entry — was left
    // completely unhandled, so _loading never got set back to false and
    // the sheet was stuck showing a spinner forever. A failed cache read
    // isn't fatal either way: just fall through to the live refresh below.
    try {
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
    } catch (e) {
      // Ignored — the live refresh below is the real source of truth.
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
          _notAMember = e is FunctionException && e.status == 403;
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
      // Not an error at all — a signed-in guest or staff account simply
      // doesn't have a card yet. Its own screen, not a scary red error,
      // since "the card won't load" was being read as a bug rather than
      // an accurate status (feedback).
      if (_notAMember) {
        return SizedBox(
          height: 320,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(FlcSpace.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.card_membership_outlined, color: Colors.white70, size: 32),
                  const SizedBox(height: FlcSpace.sm),
                  const Text(
                    "You're not a member yet",
                    style: FlcTextStyles.h3,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: FlcSpace.xxs),
                  Text(
                    'Once the club activates your card, it will show up here.',
                    style: FlcTextStyles.body.copyWith(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: FlcSpace.md),
                  FilledButton(
                    onPressed: () => context.push('/you/become-a-member'),
                    child: const Text('Become a member'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
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
        const MembershipCardWordmark(),
        const SizedBox(height: FlcSpace.xs),
        Text(
          card.fullName,
          style: const TextStyle(
            fontFamily: FlcFontFamily.serif,
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        if (card.membershipKind != null || card.validTo != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            <String>[
              if (card.membershipKind != null) '${_kindLabel(card.membershipKind!)} member',
              if (card.validTo != null) 'Valid to ${dateFormat.format(card.validTo!)}',
            ].join(' · '),
            style: FlcTextStyles.caption.copyWith(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: FlcSpace.md),
        // The scan panel — photo and QR at matching size, side by side
        // (briefing feedback, 2026-08-24), barcode + number underneath.
        // One cream surface, not three separate floating blocks.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(FlcSpace.sm, FlcSpace.sm, FlcSpace.sm, FlcSpace.xs),
          decoration: BoxDecoration(color: const Color(0xFFFBF9F2), borderRadius: BorderRadius.circular(FlcRadius.card)),
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _Photo(path: _photoPath),
                  const SizedBox(width: FlcSpace.sm),
                  _QrArea(payload: _payload),
                ],
              ),
              if (card.membershipNumber != null) ...<Widget>[
                const SizedBox(height: FlcSpace.sm),
                const _DashedDivider(),
                const SizedBox(height: FlcSpace.xs),
                bw.BarcodeWidget(
                  barcode: bw.Barcode.code128(),
                  data: card.membershipNumber!,
                  height: 36,
                  drawText: false,
                  color: const Color(0xFF202B08),
                ),
                const SizedBox(height: 2),
                Text(
                  card.membershipNumber!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, letterSpacing: 1, color: Color(0xFF202B08)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: FlcSpace.sm),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: FlcSpace.xxs),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFB7CC6C)),
            ),
            Flexible(
              child: Text(
                'QR rotates every 30s for staff to scan',
                style: FlcTextStyles.caption.copyWith(color: Colors.white60),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        if (card.membershipPin != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            'PIN  ${card.membershipPin}',
            style: FlcTextStyles.bodySmall.copyWith(color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: 3),
          ),
        ],
        const SizedBox(height: FlcSpace.xs),
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
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(FlcRadius.input),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[Color(0xFFEDEAE0), Color(0xFFDFDBCC)],
      ),
    );
    if (path == null) {
      return Container(
        width: _kIdBlockSize,
        height: _kIdBlockSize,
        decoration: decoration,
        child: const Icon(Icons.person, color: Color(0xFFB9BEA3), size: 44),
      );
    }
    return Container(
      width: _kIdBlockSize,
      height: _kIdBlockSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FlcRadius.input),
        image: DecorationImage(image: FileImage(File(path!)), fit: BoxFit.cover),
      ),
    );
  }
}

class _QrArea extends StatelessWidget {
  const _QrArea({required this.payload});

  final String? payload;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kIdBlockSize,
      height: _kIdBlockSize,
      alignment: Alignment.center,
      child: payload == null
          ? const CircularProgressIndicator()
          : QrImageView(data: payload!, size: _kIdBlockSize, backgroundColor: const Color(0xFFFBF9F2)),
    );
  }
}

/// A quiet stand-in for the mockup's dashed rule between the QR/photo pair
/// and the barcode — Flutter has no built-in dashed border, so this draws
/// one from a row of short segments rather than pulling in a package for a
/// single hairline.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 4.0;
        const gap = 3.0;
        final count = (constraints.maxWidth / (dashWidth + gap)).floor();
        return SizedBox(
          height: 1,
          child: Row(
            children: List<Widget>.generate(
              count,
              (_) => const Padding(
                padding: EdgeInsets.only(right: gap),
                child: SizedBox(width: dashWidth, height: 1, child: ColoredBox(color: Color(0xFFD8D2BE))),
              ),
            ),
          ),
        );
      },
    );
  }
}
