import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'presentation/tickets_feed_controller.dart';

/// My tickets — briefing §9.4. Rotating signed QR, FLAG_SECURE, offline
/// rendering from local secure storage happen on the detail screen this
/// pushes to; this screen itself is the offline-first list, same
/// stale-while-revalidate shape as the events feed.
class TicketsScreen extends ConsumerWidget {
  const TicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(ticketsFeedControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My tickets')),
      body: ticketsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorState(onRetry: () => ref.read(ticketsFeedControllerProvider.notifier).refresh()),
        data: (tickets) {
          if (tickets.isEmpty) return const _EmptyState();

          final upcoming = tickets.where((t) => t.isUpcoming).toList()
            ..sort((a, b) => a.eventStartsAt.compareTo(b.eventStartsAt));
          final past = tickets.where((t) => !t.isUpcoming).toList()
            ..sort((a, b) => b.eventStartsAt.compareTo(a.eventStartsAt));

          return RefreshIndicator(
            onRefresh: () => ref.read(ticketsFeedControllerProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: FlcSpace.sm),
              children: <Widget>[
                if (upcoming.isNotEmpty) ...<Widget>[
                  const _SectionHeader('Upcoming'),
                  for (final ticket in upcoming) _TicketRow(ticket: ticket),
                ],
                if (past.isNotEmpty) ...<Widget>[
                  const _SectionHeader('Past'),
                  for (final ticket in past) _TicketRow(ticket: ticket),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FlcSpace.md, FlcSpace.md, FlcSpace.md, FlcSpace.xs),
      child: Text(title, style: FlcTextStyles.h3),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.ticket});

  final TicketModel ticket;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE d MMM, HH:mm');
    final bool isPast = !ticket.isUpcoming;
    final String? statusLabel = switch (ticket.status) {
      'redeemed' => 'Used',
      'refunded' => 'Refunded',
      'void' => 'Void',
      'cancelled' => 'Cancelled',
      _ => null,
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.xs),
      child: ListTile(
        leading: Icon(
          Icons.confirmation_number_outlined,
          color: isPast || statusLabel != null ? FlcColors.slate : Theme.of(context).colorScheme.primary,
        ),
        title: Text(ticket.eventTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${dateFormat.format(ticket.eventStartsAt)}'
          '${ticket.ticketTypeName != null ? ' · ${ticket.ticketTypeName}' : ''}',
        ),
        trailing: statusLabel != null
            ? Chip(label: Text(statusLabel), visualDensity: VisualDensity.compact)
            : const Icon(Icons.chevron_right),
        onTap: () => context.push('/you/tickets/${ticket.id}', extra: ticket),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FlcSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.confirmation_number_outlined, size: 40, color: FlcColors.slate),
            const SizedBox(height: FlcSpace.sm),
            const Text(
              "You don't have any tickets yet.",
              textAlign: TextAlign.center,
              style: FlcTextStyles.body,
            ),
            const SizedBox(height: FlcSpace.md),
            FilledButton(onPressed: () => context.go('/events'), child: const Text('Browse events')),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text("Couldn't load your tickets."),
          const SizedBox(height: FlcSpace.sm),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
