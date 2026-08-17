import 'dart:async';

import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/env.dart';
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

enum _Phase { starting, awaitingPaymentSheet, confirmingWithServer, timedOut, error }

class _PaymentStepState extends ConsumerState<PaymentStep> {
  _Phase _phase = _Phase.starting;
  String? _errorMessage;
  StreamSubscription<String>? _orderStatusSub;
  Timer? _confirmationTimeout;

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
    if (Env.stripePublishableKey.isEmpty) {
      return const _PaymentMessage(
        icon: Icons.payments_outlined,
        title: 'Payments aren’t configured yet',
        message: 'The club hasn’t connected a Stripe account to this build yet. Everything up to this point — '
            'the order, pricing and stock check — has already run on the server; this is the only remaining step.',
      );
    }

    switch (_phase) {
      case _Phase.starting:
      case _Phase.awaitingPaymentSheet:
        return const _PaymentMessage(icon: Icons.lock_outline, title: 'Preparing payment…', loading: true);
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
    // build() shows a "not configured" message in this case and never
    // lets the user reach a button that calls this — but initState's
    // postFrameCallback calls it unconditionally, and without this guard
    // it would still try to drive Stripe.instance, which was never
    // initialized with a publishable key (main.dart skips that too when
    // this is empty) and native calls against an uninitialized SDK are
    // not something to find out about via a Dart exception.
    if (Env.stripePublishableKey.isEmpty) return;

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

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: order.clientSecret,
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
  });

  final IconData icon;
  final String title;
  final String? message;
  final bool loading;
  final VoidCallback? onRetry;

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
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
