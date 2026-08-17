import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../loyalty/loyalty_providers.dart';

/// Briefing §9.3 step 4. "Loyalty progress updates visibly here... because
/// this is the moment of maximum receptivity" — the order confirmation
/// itself, plus this loyalty callout.
///
/// This shows current standing (refetched fresh, not the pre-purchase
/// value), not a claim that THIS purchase specifically just earned a
/// point — the client has no reliable way to attribute that without a
/// before/after comparison, and the server already silently no-ops a
/// second point for the same event (§10.1), so overclaiming here would
/// sometimes just be wrong.
class ConfirmationStep extends ConsumerWidget {
  const ConfirmationStep({required this.reference, super.key});

  final String reference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loyalty = ref.watch(loyaltyStatusProvider).valueOrNull;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FlcSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.check_circle, size: 56, color: FlcColors.success),
            const SizedBox(height: FlcSpace.md),
            const Text('You’re booked in', style: FlcTextStyles.h2, textAlign: TextAlign.center),
            const SizedBox(height: FlcSpace.xs),
            Text('Order $reference', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate)),
            if (loyalty != null) ...<Widget>[
              const SizedBox(height: FlcSpace.lg),
              _LoyaltyCallout(loyalty: loyalty),
            ],
            const SizedBox(height: FlcSpace.lg),
            FilledButton(
              onPressed: () => context.go('/you/tickets'),
              child: const Text('View your ticket'),
            ),
            const SizedBox(height: FlcSpace.sm),
            OutlinedButton(
              onPressed: () => context.go('/events'),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoyaltyCallout extends StatelessWidget {
  const _LoyaltyCallout({required this.loyalty});

  final LoyaltyStatus loyalty;

  @override
  Widget build(BuildContext context) {
    final hasAvailableReward = loyalty.rewards.any((r) => r.isAvailable);
    final threshold = loyalty.config.threshold;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.sm),
      decoration: BoxDecoration(
        color: FlcColors.paper,
        borderRadius: BorderRadius.circular(FlcRadius.card),
        border: Border.all(color: FlcColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(hasAvailableReward ? Icons.card_giftcard : Icons.loyalty_outlined, size: 18, color: FlcColors.red),
          const SizedBox(width: FlcSpace.xs),
          Text(
            hasAvailableReward
                ? 'You have a free ticket ready to use'
                : 'Loyalty: ${loyalty.balance} of $threshold toward your next free ticket',
            style: FlcTextStyles.bodySmall,
          ),
        ],
      ),
    );
  }
}
