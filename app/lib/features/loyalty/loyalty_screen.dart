import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/supabase/supabase_providers.dart';
import 'loyalty_providers.dart';

/// Loyalty progress + ledger — briefing §9.5, §10. One point per event per
/// person; the ledger below is already event-level by construction (the
/// database enforces at most one 'purchase' entry per event per person),
/// so there's nothing to group — each row already IS one event, never one
/// ticket.
class LoyaltyScreen extends ConsumerWidget {
  const LoyaltyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(currentUserProvider) != null;

    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loyalty')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(FlcSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.loyalty_outlined, size: 40, color: FlcColors.slate),
                const SizedBox(height: FlcSpace.sm),
                const Text('Sign in to track your loyalty progress.', style: FlcTextStyles.body, textAlign: TextAlign.center),
                const SizedBox(height: FlcSpace.md),
                FilledButton(onPressed: () => context.push('/sign-in'), child: const Text('Sign in')),
              ],
            ),
          ),
        ),
      );
    }

    final statusAsync = ref.watch(loyaltyStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Loyalty')),
      body: statusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text("Couldn't load your loyalty progress."),
              const SizedBox(height: FlcSpace.sm),
              OutlinedButton(onPressed: () => ref.invalidate(loyaltyStatusProvider), child: const Text('Retry')),
            ],
          ),
        ),
        data: (status) {
          if (status == null) return const SizedBox.shrink();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(loyaltyStatusProvider),
            child: ListView(
              padding: const EdgeInsets.all(FlcSpace.md),
              children: <Widget>[
                _ProgressCard(status: status),
                if (status.rewards.any((r) => r.isAvailable)) ...<Widget>[
                  const SizedBox(height: FlcSpace.md),
                  _AvailableRewardsCard(count: status.rewards.where((r) => r.isAvailable).length),
                ],
                const SizedBox(height: FlcSpace.lg),
                const Text('Activity', style: FlcTextStyles.h3),
                const SizedBox(height: FlcSpace.sm),
                if (status.ledger.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: FlcSpace.md),
                    child: Text(
                      'Buy a ticket to start earning — one point per event, however many tickets you buy to it.',
                      style: FlcTextStyles.body,
                    ),
                  )
                else
                  for (final entry in status.ledger) _LedgerRow(entry: entry, eventTitles: status.eventTitles),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.status});

  final LoyaltyStatus status;

  @override
  Widget build(BuildContext context) {
    final threshold = status.config.threshold;
    final progress = threshold == 0 ? 0.0 : (status.balance / threshold).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FlcSpace.md),
      decoration: BoxDecoration(color: FlcColors.ink, borderRadius: BorderRadius.circular(FlcRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${status.balance} of $threshold',
            style: FlcTextStyles.h2.copyWith(color: Colors.white),
          ),
          const SizedBox(height: FlcSpace.xxs),
          Text(
            'tickets toward your next free one',
            style: FlcTextStyles.body.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: FlcSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(FlcColors.brand),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableRewardsCard extends StatelessWidget {
  const _AvailableRewardsCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FlcSpace.md),
      decoration: BoxDecoration(
        color: FlcColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(FlcRadius.card),
        border: Border.all(color: FlcColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.card_giftcard, color: FlcColors.success),
          const SizedBox(width: FlcSpace.sm),
          Expanded(
            child: Text(
              count == 1
                  ? 'You have a free ticket ready — apply it at checkout on your next booking.'
                  : 'You have $count free tickets ready — apply one at checkout on your next booking.',
              style: FlcTextStyles.body,
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry, required this.eventTitles});

  final LoyaltyLedgerEntryModel entry;
  final Map<String, String> eventTitles;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMM yyyy');
    final bool positive = entry.delta > 0;
    final String title = entry.eventId != null
        ? (eventTitles[entry.eventId] ?? 'Event ticket')
        : _reasonLabel(entry.reason);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FlcSpace.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: FlcTextStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(dateFormat.format(entry.createdAt), style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate)),
              ],
            ),
          ),
          Text(
            '${positive ? '+' : ''}${entry.delta}',
            style: FlcTextStyles.body.copyWith(
              color: positive ? FlcColors.success : FlcColors.slate,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _reasonLabel(String reason) => switch (reason) {
        'reward_granted' => 'Free ticket earned',
        'reward_redeemed' => 'Free ticket used',
        'refund_reversal' => 'Point reversed (refund)',
        'manual_adjustment' => 'Adjustment',
        _ => 'Loyalty update',
      };
}
