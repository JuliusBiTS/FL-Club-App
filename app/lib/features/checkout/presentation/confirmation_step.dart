import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Briefing §9.3 step 4. "Loyalty progress updates visibly here... because
/// this is the moment of maximum receptivity" — that part is M7 scope
/// (needs the loyalty ledger to exist first); the order confirmation
/// itself is real now.
class ConfirmationStep extends StatelessWidget {
  const ConfirmationStep({required this.reference, super.key});

  final String reference;

  @override
  Widget build(BuildContext context) {
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
