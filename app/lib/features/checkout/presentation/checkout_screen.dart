import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../account/presentation/auth_form.dart';
import '../../loyalty/loyalty_providers.dart';
import '../domain/checkout_args.dart';
import 'confirmation_step.dart';
import 'payment_step.dart';

enum _CheckoutStep { review, account, payment, confirmation }

/// Briefing §9.3: "Four steps, one screen each, with a progress indicator.
/// Never more than four." Account is skipped entirely when already signed
/// in — it isn't shown as a no-op step, the progress indicator's step
/// count just accounts for it being possible.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({required this.args, super.key});

  final CheckoutArgs args;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  _CheckoutStep _step = _CheckoutStep.review;
  String? _orderReference;
  bool _useLoyaltyReward = false;
  bool _acceptedTerms = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        automaticallyImplyLeading: _step == _CheckoutStep.review,
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (_step != _CheckoutStep.confirmation) _StepProgress(step: _step),
            Expanded(
              child: switch (_step) {
                _CheckoutStep.review => SingleChildScrollView(
                    padding: const EdgeInsets.all(FlcSpace.md),
                    child: _ReviewStep(
                      args: widget.args,
                      useLoyaltyReward: _useLoyaltyReward,
                      onUseLoyaltyRewardChanged: (value) => setState(() => _useLoyaltyReward = value),
                      acceptedTerms: _acceptedTerms,
                      onAcceptedTermsChanged: (value) => setState(() => _acceptedTerms = value),
                      onContinue: _handleContinueFromReview,
                    ),
                  ),
                _CheckoutStep.account => Padding(
                    padding: const EdgeInsets.all(FlcSpace.md),
                    child: SingleChildScrollView(
                      child: AuthForm(onAuthenticated: () => setState(() => _step = _CheckoutStep.payment)),
                    ),
                  ),
                _CheckoutStep.payment => PaymentStep(
                    args: widget.args,
                    useLoyaltyReward: _useLoyaltyReward,
                    onPaid: (orderId, reference) => setState(() {
                      _orderReference = reference;
                      _step = _CheckoutStep.confirmation;
                      // mark_order_paid already ran server-side by the time
                      // this fires (it's what flips the order to 'paid' in
                      // the first place) — invalidate so the confirmation
                      // screen's loyalty callout shows the real post-
                      // purchase standing, not whatever was cached before.
                      ref.invalidate(loyaltyStatusProvider);
                    }),
                  ),
                _CheckoutStep.confirmation => ConfirmationStep(reference: _orderReference ?? ''),
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleContinueFromReview() {
    final isSignedIn = ref.read(currentUserProvider) != null;
    setState(() => _step = isSignedIn ? _CheckoutStep.payment : _CheckoutStep.account);
  }
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.step});

  final _CheckoutStep step;

  @override
  Widget build(BuildContext context) {
    final index = _CheckoutStep.values.indexOf(step);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.xs),
      child: LinearProgressIndicator(value: (index + 1) / (_CheckoutStep.values.length - 1)),
    );
  }
}

class _ReviewStep extends ConsumerWidget {
  const _ReviewStep({
    required this.args,
    required this.useLoyaltyReward,
    required this.onUseLoyaltyRewardChanged,
    required this.acceptedTerms,
    required this.onAcceptedTermsChanged,
    required this.onContinue,
  });

  final CheckoutArgs args;
  final bool useLoyaltyReward;
  final ValueChanged<bool> onUseLoyaltyRewardChanged;
  final bool acceptedTerms;
  final ValueChanged<bool> onAcceptedTermsChanged;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rewardCountAsync = ref.watch(availableRewardCountProvider);
    final hasReward = (rewardCountAsync.valueOrNull ?? 0) > 0;
    // Discounts exactly one unit, same as the server (§10.2) — this is a
    // preview only, the authoritative total comes back from create-order.
    final discountMinor = useLoyaltyReward && hasReward ? args.pricePerUnitMinor : 0;
    final totalAfterDiscount = args.subtotalMinor - discountMinor;

    final unitDisplay = args.pricePerUnitMinor == 0 ? 'Free' : '£${(args.pricePerUnitMinor / 100).toStringAsFixed(2)}';
    final totalDisplay = totalAfterDiscount == 0 ? 'Free' : '£${(totalAfterDiscount / 100).toStringAsFixed(2)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(args.eventTitle, style: FlcTextStyles.h3),
        const SizedBox(height: FlcSpace.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(FlcSpace.md),
            child: Column(
              children: <Widget>[
                _SummaryRow(label: args.ticketTypeName, value: '${args.quantity} × $unitDisplay'),
                if (discountMinor > 0) ...<Widget>[
                  const Divider(),
                  _SummaryRow(label: 'Free ticket applied', value: '-£${(discountMinor / 100).toStringAsFixed(2)}'),
                ],
                const Divider(),
                _SummaryRow(label: 'Total', value: totalDisplay, emphasize: true),
              ],
            ),
          ),
        ),
        if (hasReward) ...<Widget>[
          const SizedBox(height: FlcSpace.sm),
          CheckboxListTile(
            value: useLoyaltyReward,
            onChanged: (value) => onUseLoyaltyRewardChanged(value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.card_giftcard, color: FlcColors.success),
            title: const Text('Use your free ticket'),
            subtitle: const Text('Covers one ticket in this order at this price.'),
          ),
        ],
        const SizedBox(height: FlcSpace.lg),
        Text(
          'The Frontline Club Charitable Trust — UK registered charity no. 1111898.',
          style: FlcTextStyles.caption.copyWith(color: FlcColors.slate),
        ),
        const SizedBox(height: FlcSpace.sm),
        CheckboxListTile(
          value: acceptedTerms,
          onChanged: (value) => onAcceptedTermsChanged(value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('I understand tickets are non-refundable unless the event is cancelled or postponed.'),
        ),
        const SizedBox(height: FlcSpace.md),
        FilledButton(
          onPressed: acceptedTerms ? onContinue : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.emphasize = false});

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
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
