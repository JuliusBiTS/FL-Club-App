import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../loyalty/loyalty_providers.dart';
import 'membership_card_wordmark.dart';

/// The card's back face — briefing feedback from the club's design lead,
/// modelled directly on Waterstones Plus's stamp-grid back (10 stamps,
/// crosses for earned, an outline for the next one due). Reuses the
/// loyalty balance/threshold that already drives the Loyalty tab
/// (loyalty_providers.dart) — no new backend, this is a second view onto
/// the same data.
class MembershipCardBack extends ConsumerWidget {
  const MembershipCardBack({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(loyaltyStatusProvider);

    return statusAsync.when(
      loading: () => const SizedBox(height: 320, child: Center(child: CircularProgressIndicator(color: Colors.white))),
      error: (error, stackTrace) => const SizedBox(
        height: 320,
        child: Center(child: Icon(Icons.error_outline, color: Colors.white70, size: 32)),
      ),
      data: (status) {
        if (status == null) return const SizedBox(height: 320);
        final threshold = status.config.threshold;
        final filled = status.balance >= threshold ? threshold : status.balance;
        final remaining = threshold - filled;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const MembershipCardWordmark(compact: true),
            const SizedBox(height: FlcSpace.md),
            Text('Loyalty stamps', style: FlcTextStyles.h3.copyWith(color: Colors.white)),
            const SizedBox(height: FlcSpace.xxs),
            Text(
              remaining == 0
                  ? 'Free ticket earned — redeem it at checkout'
                  : '$remaining more event${remaining == 1 ? '' : 's'} for a free ticket',
              style: FlcTextStyles.bodySmall.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FlcSpace.md),
            _StampGrid(filled: filled, total: threshold),
            const SizedBox(height: FlcSpace.md),
            Text(
              '1 stamp per event attended · $threshold stamps = 1 free ticket',
              style: FlcTextStyles.caption.copyWith(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    );
  }
}

class _StampGrid extends StatelessWidget {
  const _StampGrid({required this.filled, required this.total});

  final int filled;
  final int total;

  @override
  Widget build(BuildContext context) {
    const perRow = 5;
    final rows = (total / perRow).ceil();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var row = 0; row < rows; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: FlcSpace.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var col = 0; col < perRow && row * perRow + col < total; col++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: FlcSpace.xs),
                    child: _Stamp(earned: row * perRow + col < filled),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.earned});

  final bool earned;

  @override
  Widget build(BuildContext context) {
    const size = 34.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: earned ? const Color(0xFFFBF9F2) : Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
      ),
      child: earned ? const Icon(Icons.close, size: 18, color: Color(0xFF202B08)) : null,
    );
  }
}
