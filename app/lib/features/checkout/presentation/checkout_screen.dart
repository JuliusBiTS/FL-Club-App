import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../account/presentation/auth_form.dart';
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
                    child: _ReviewStep(args: widget.args, onContinue: _handleContinueFromReview),
                  ),
                _CheckoutStep.account => Padding(
                    padding: const EdgeInsets.all(FlcSpace.md),
                    child: SingleChildScrollView(
                      child: AuthForm(onAuthenticated: () => setState(() => _step = _CheckoutStep.payment)),
                    ),
                  ),
                _CheckoutStep.payment => PaymentStep(
                    args: widget.args,
                    onPaid: (orderId, reference) => setState(() {
                      _orderReference = reference;
                      _step = _CheckoutStep.confirmation;
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

class _ReviewStep extends StatefulWidget {
  const _ReviewStep({required this.args, required this.onContinue});

  final CheckoutArgs args;
  final VoidCallback onContinue;

  @override
  State<_ReviewStep> createState() => _ReviewStepState();
}

class _ReviewStepState extends State<_ReviewStep> {
  bool _acceptedTerms = false;

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final unitDisplay = args.pricePerUnitMinor == 0 ? 'Free' : '£${(args.pricePerUnitMinor / 100).toStringAsFixed(2)}';
    final totalDisplay = args.subtotalMinor == 0 ? 'Free' : '£${(args.subtotalMinor / 100).toStringAsFixed(2)}';

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
                const Divider(),
                _SummaryRow(label: 'Total', value: totalDisplay, emphasize: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: FlcSpace.lg),
        Text(
          'The Frontline Club Charitable Trust — UK registered charity no. 1111898.',
          style: FlcTextStyles.caption.copyWith(color: FlcColors.slate),
        ),
        const SizedBox(height: FlcSpace.sm),
        CheckboxListTile(
          value: _acceptedTerms,
          onChanged: (value) => setState(() => _acceptedTerms = value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('I understand tickets are non-refundable unless the event is cancelled or postponed.'),
        ),
        const SizedBox(height: FlcSpace.md),
        FilledButton(
          onPressed: _acceptedTerms ? widget.onContinue : null,
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
