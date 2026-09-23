import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../loyalty/loyalty_providers.dart';
import '../domain/checkout_args.dart';

/// Briefing §9.3 step 4. "Loyalty progress updates visibly here... because
/// this is the moment of maximum receptivity" — the order confirmation
/// itself, plus this loyalty callout.
///
/// Feedback: this used to be just an icon and a reference number — "give
/// it an overview with the order details, and maybe a 'thank you for
/// supporting independent journalism' [message] like the splash screen".
/// Order details are exactly what was already shown for confirmation on
/// the review step (CheckoutArgs), not re-fetched, so they can never
/// disagree with what the person just agreed to pay.
///
/// The loyalty callout shows current standing (refetched fresh, not the
/// pre-purchase value), not a claim that THIS purchase specifically just
/// earned a point — the client has no reliable way to attribute that
/// without a before/after comparison, and the server already silently
/// no-ops a second point for the same event (§10.1), so overclaiming here
/// would sometimes just be wrong.
class ConfirmationStep extends ConsumerWidget {
  const ConfirmationStep({required this.reference, required this.args, this.usedLoyaltyReward = false, super.key});

  final String reference;
  final CheckoutArgs args;
  final bool usedLoyaltyReward;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loyalty = ref.watch(loyaltyStatusProvider).valueOrNull;
    // Same estimate already confirmed on the review step — the
    // authoritative charge is whatever create-order/Stripe actually took;
    // this is a summary of what was agreed to, not a legal receipt.
    final int discountMinor = usedLoyaltyReward ? args.pricePerUnitMinor : 0;
    final int totalMinor = args.subtotalMinor - discountMinor;
    final String totalDisplay = totalMinor == 0 ? 'Free' : '£${(totalMinor / 100).toStringAsFixed(2)}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(FlcSpace.lg),
      child: Column(
        children: <Widget>[
          Icon(Icons.check_circle, size: 56, color: FlcColors.successAccent(context)),
          const SizedBox(height: FlcSpace.md),
          const Text('You’re booked in', style: FlcTextStyles.h2, textAlign: TextAlign.center),
          const SizedBox(height: FlcSpace.xs),
          Text('Order $reference', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context))),
          const SizedBox(height: FlcSpace.lg),
          _OrderDetailsCard(args: args, discountMinor: discountMinor, totalDisplay: totalDisplay),
          if (loyalty != null) ...<Widget>[
            const SizedBox(height: FlcSpace.md),
            _LoyaltyCallout(loyalty: loyalty),
          ],
          const SizedBox(height: FlcSpace.lg),
          const _ThankYouBanner(),
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
    );
  }
}

class _OrderDetailsCard extends StatelessWidget {
  const _OrderDetailsCard({required this.args, required this.discountMinor, required this.totalDisplay});

  final CheckoutArgs args;
  final int discountMinor;
  final String totalDisplay;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FlcSpace.md),
      decoration: BoxDecoration(
        border: Border.all(color: FlcColors.line),
        borderRadius: BorderRadius.circular(FlcRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(args.eventTitle, style: FlcTextStyles.h3),
          const SizedBox(height: FlcSpace.sm),
          _Row(label: args.ticketTypeName, value: '× ${args.quantity}'),
          if (discountMinor > 0) _Row(label: 'Free ticket applied', value: '-£${(discountMinor / 100).toStringAsFixed(2)}'),
          const Divider(height: FlcSpace.lg),
          _Row(label: 'Total paid', value: totalDisplay, emphasize: true),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize ? FlcTextStyles.h3 : FlcTextStyles.body;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FlcSpace.xxs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// A small, quieter echo of the boot splash (same brand olive, same Jost
/// strapline font) rather than a second full-screen animated takeover —
/// this is one line inside an already-busy confirmation flow, not a first
/// impression, so it earns a nod to that moment rather than a repeat of it.
class _ThankYouBanner extends StatelessWidget {
  const _ThankYouBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.md),
      decoration: BoxDecoration(color: FlcColors.brand, borderRadius: BorderRadius.circular(FlcRadius.card)),
      child: const Text(
        'THANK YOU FOR SUPPORTING\nINDEPENDENT JOURNALISM',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Jost',
          fontWeight: FontWeight.w600,
          fontSize: 16,
          height: 1.4,
          letterSpacing: 1.2,
          color: Colors.white,
          decoration: TextDecoration.none,
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
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.sm),
      decoration: BoxDecoration(
        color: FlcColors.paper,
        borderRadius: BorderRadius.circular(FlcRadius.card),
        border: Border.all(color: FlcColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(hasAvailableReward ? Icons.card_giftcard : Icons.loyalty_outlined, size: 18, color: FlcColors.brand),
          const SizedBox(width: FlcSpace.xs),
          Flexible(
            child: Text(
              hasAvailableReward
                  ? 'You have a free ticket ready to use'
                  : 'Loyalty: ${loyalty.balance} of $threshold toward your next free ticket',
              style: FlcTextStyles.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
