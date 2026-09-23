import 'dart:async';

import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/checkout_repository.dart';
import '../domain/checkout_args.dart';

/// Briefing §9.3 step 3-5. create-order -> PaymentSheet -> wait for the
/// order's own row to flip to 'paid' via Realtime. The app never creates
/// a ticket itself — if the webhook is slow, this shows "Confirming your
/// payment…" with a 60s timeout and a "we'll email you" fallback rather
/// than a false failure (§9.3 step 5).
class PaymentStep extends ConsumerStatefulWidget {
  const PaymentStep({required this.args, required this.onPaid, this.useLoyaltyReward = false, super.key});

  final CheckoutArgs args;
  final void Function(String orderId, String reference) onPaid;
  final bool useLoyaltyReward;

  @override
  ConsumerState<PaymentStep> createState() => _PaymentStepState();
}

enum _Phase { starting, awaitingPaymentSheet, testReady, completingTestPayment, confirmingWithServer, timedOut, error }

class _PaymentStepState extends ConsumerState<PaymentStep> {
  _Phase _phase = _Phase.starting;
  String? _errorMessage;
  StreamSubscription<String>? _orderStatusSub;
  Timer? _confirmationTimeout;

  // Only set in test mode (see _Phase.testReady) — held between create-order
  // and the person tapping "Complete test payment".
  String? _testOrderId;
  String? _testReference;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _orderStatusSub?.cancel();
    _confirmationTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.starting:
      case _Phase.awaitingPaymentSheet:
        return const _PaymentMessage(icon: Icons.lock_outline, title: 'Preparing payment…', loading: true);
      case _Phase.testReady:
        // The server has no Stripe account connected yet — feedback: "put
        // a placeholder payment feature so the whole ticketing process can
        // go through and be tested." Everything up to here (the order,
        // pricing, stock check) already ran for real; this is a stand-in
        // for the one remaining step, clearly labelled as such so it's
        // never mistaken for a real charge.
        return _PaymentMessage(
          icon: Icons.science_outlined,
          title: 'Test payment — no Stripe account connected',
          message: 'No money will be taken. Tapping below marks this order paid exactly like a real payment '
              'would, so tickets, loyalty and the confirmation screen can all be tested end to end.',
          onRetry: _completeTestPayment,
          retryLabel: 'Complete test payment',
        );
      case _Phase.completingTestPayment:
        return const _PaymentMessage(icon: Icons.science_outlined, title: 'Completing test payment…', loading: true);
      case _Phase.confirmingWithServer:
        return const _PaymentMessage(icon: Icons.hourglass_top_outlined, title: 'Confirming your payment…', loading: true);
      case _Phase.timedOut:
        return const _PaymentMessage(
          icon: Icons.mark_email_unread_outlined,
          title: 'This is taking longer than usual',
          message: "We'll email your confirmation as soon as it's through — no need to wait here or pay again.",
        );
      case _Phase.error:
        return _PaymentMessage(
          icon: Icons.error_outline,
          title: 'Payment not completed',
          message: _errorMessage ?? 'Something went wrong. No money has been taken.',
          onRetry: _start,
        );
    }
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.starting;
      _errorMessage = null;
    });

    try {
      final order = await ref.read(checkoutRepositoryProvider).createOrder(
            eventId: widget.args.eventId,
            ticketTypeId: widget.args.ticketTypeId,
            quantity: widget.args.quantity,
            useLoyaltyReward: widget.useLoyaltyReward,
          );

      if (order.testMode) {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.testReady;
          _testOrderId = order.orderId;
          _testReference = order.reference;
        });
        return;
      }

      // Real Stripe path. Never reached in test mode, so Stripe.instance —
      // never initialized with a key when Env.stripePublishableKey is
      // empty (see main.dart) — is never touched in that case either.
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: order.clientSecret!,
          merchantDisplayName: 'The Frontline Club',
        ),
      );

      if (!mounted) return;
      setState(() => _phase = _Phase.awaitingPaymentSheet);
      await Stripe.instance.presentPaymentSheet();

      // Stripe accepting the payment method doesn't mean the order is
      // 'paid' yet — stripe-webhook does that asynchronously. Only the
      // Realtime subscription on the order's own row is the source of
      // truth for that (briefing §9.3 step 5).
      if (!mounted) return;
      setState(() => _phase = _Phase.confirmingWithServer);
      _watchForPaid(order.orderId, order.reference);
    } on StripeException catch (e) {
      if (!mounted) return;
      final isUserCancelled = e.error.code == FailureCode.Canceled;
      setState(() {
        _phase = isUserCancelled ? _Phase.starting : _Phase.error;
        _errorMessage = isUserCancelled ? null : e.error.localizedMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        // create-order surfaces reserve_order_inventory's validation errors
        // as plain English (§16.4) — e.g. "No free ticket is available to
        // use." if the reward was spent elsewhere between page load and
        // submit. Show that directly rather than a generic message.
        _errorMessage = e is FunctionException ? _serverMessage(e) : 'Something went wrong. No money has been taken.';
      });
    }
  }

  Future<void> _completeTestPayment() async {
    final orderId = _testOrderId;
    final reference = _testReference;
    if (orderId == null || reference == null) return;

    setState(() => _phase = _Phase.completingTestPayment);
    try {
      await ref.read(checkoutRepositoryProvider).simulateTestPayment(orderId);
      if (!mounted) return;
      setState(() => _phase = _Phase.confirmingWithServer);
      _watchForPaid(orderId, reference);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = e is FunctionException ? _serverMessage(e) : 'Something went wrong completing the test payment.';
      });
    }
  }

  String _serverMessage(FunctionException e) {
    final details = e.details;
    if (details is Map && details['error'] is String) return details['error'] as String;
    return 'Something went wrong. No money has been taken.';
  }

  void _watchForPaid(String orderId, String reference) {
    _confirmationTimeout = Timer(const Duration(seconds: 60), () {
      if (mounted && _phase == _Phase.confirmingWithServer) {
        setState(() => _phase = _Phase.timedOut);
      }
    });

    _orderStatusSub = ref.read(checkoutRepositoryProvider).watchOrderStatus(orderId).listen((status) {
      if (!mounted) return;
      if (status == 'paid') {
        _confirmationTimeout?.cancel();
        widget.onPaid(orderId, reference);
      } else if (status == 'failed' || status == 'cancelled') {
        _confirmationTimeout?.cancel();
        setState(() {
          _phase = _Phase.error;
          _errorMessage = 'Your payment did not go through. No money has been taken.';
        });
      }
    });
  }
}

class _PaymentMessage extends StatelessWidget {
  const _PaymentMessage({
    required this.icon,
    required this.title,
    this.message,
    this.loading = false,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  final IconData icon;
  final String title;
  final String? message;
  final bool loading;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FlcSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (loading)
              const SizedBox(height: 40, width: 40, child: CircularProgressIndicator())
            else
              Icon(icon, size: 40, color: FlcColors.slate),
            const SizedBox(height: FlcSpace.md),
            Text(title, style: FlcTextStyles.h3, textAlign: TextAlign.center),
            if (message != null) ...<Widget>[
              const SizedBox(height: FlcSpace.sm),
              Text(message!, style: FlcTextStyles.body.copyWith(color: FlcColors.slate), textAlign: TextAlign.center),
            ],
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: FlcSpace.md),
              FilledButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ],
        ),
      ),
    );
  }
}
