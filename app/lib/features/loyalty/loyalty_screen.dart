import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/supabase/supabase_providers.dart';
import 'loyalty_providers.dart';
import 'loyalty_widgets.dart';

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
                Icon(Icons.loyalty_outlined, size: 40, color: FlcColors.secondary(context)),
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
          final rewards = status.rewards.where((r) => r.isAvailable).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(loyaltyStatusProvider),
            child: ListView(
              padding: const EdgeInsets.all(FlcSpace.md),
              children: <Widget>[
                PunchCard(balance: status.balance, threshold: status.config.threshold, rewardsReady: rewards.length),
                if (rewards.isNotEmpty) ...<Widget>[
                  const SizedBox(height: FlcSpace.lg),
                  Text(rewards.length == 1 ? 'YOUR FREE TICKET' : 'YOUR FREE TICKETS', style: FlcTextStyles.overline.copyWith(color: FlcColors.secondary(context))),
                  const SizedBox(height: FlcSpace.sm),
                  for (final r in rewards) ...<Widget>[
                    RewardTicket(earnedAt: r.earnedAt, expiresAt: r.expiresAt),
                    const SizedBox(height: FlcSpace.sm),
                  ],
                ],
                const SizedBox(height: FlcSpace.md),
                LoyaltyHowItWorks(threshold: status.config.threshold),
                const SizedBox(height: FlcSpace.lg),
                Text('ACTIVITY', style: FlcTextStyles.overline.copyWith(color: FlcColors.secondary(context))),
                const SizedBox(height: FlcSpace.sm),
                if (status.ledger.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: FlcSpace.md),
                    child: Text(
                      'Book an event to earn your first stamp.',
                      style: FlcTextStyles.body,
                    ),
                  )
                else
                  for (int i = 0; i < status.ledger.length; i++)
                    _ActivityRow(entry: status.ledger[i], eventTitles: status.eventTitles, isLast: i == status.ledger.length - 1),
                const SizedBox(height: FlcSpace.xl),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One line of history on a thin timeline: a dot, the event, the date, the stamp.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry, required this.eventTitles, required this.isLast});

  final LoyaltyLedgerEntryModel entry;
  final Map<String, String> eventTitles;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final bool positive = entry.delta > 0;
    final bool reward = entry.reason == 'reward_granted' || entry.reason == 'reward_redeemed';
    final String title = entry.eventId != null ? (eventTitles[entry.eventId] ?? 'Event ticket') : _reasonLabel(entry.reason);
    final Color dot = reward ? FlcColors.warning : (positive ? FlcColors.accent(context) : FlcColors.secondary(context));

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 28,
            child: Column(
              children: <Widget>[
                const SizedBox(height: 6),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: reward ? dot : Colors.transparent, border: Border.all(color: dot, width: 2), shape: BoxShape.circle),
                ),
                if (!isLast) Expanded(child: Container(width: 2, color: FlcColors.secondary(context).withValues(alpha: 0.25))),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: FlcSpace.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: FlcTextStyles.body.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                        Text(DateFormat('d MMM yyyy').format(entry.createdAt), style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context))),
                      ],
                    ),
                  ),
                  Text(
                    reward ? (entry.reason == 'reward_granted' ? 'Free ticket' : 'Used') : '${positive ? '+' : ''}${entry.delta}',
                    style: FlcTextStyles.body.copyWith(color: dot, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _reasonLabel(String reason) => switch (reason) {
        'reward_granted' => 'Free ticket earned',
        'reward_redeemed' => 'Free ticket used',
        'refund_reversal' => 'Stamp reversed (refund)',
        'manual_adjustment' => 'Adjustment',
        _ => 'Loyalty update',
      };
}
