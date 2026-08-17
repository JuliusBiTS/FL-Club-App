import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Briefing §9.12: "search, view, resend confirmation, refund (full or
/// partial, via Stripe, which reverses the loyalty ledger entries
/// automatically)." Resend-confirmation is left for later (needs email
/// sending, not built anywhere yet); search is a simple client-side
/// filter on what's already loaded rather than a server-side query, fine
/// at the club's order volume.
class OrdersSection extends StatefulWidget {
  const OrdersSection({super.key});

  @override
  State<OrdersSection> createState() => _OrdersSectionState();
}

class _OrdersSectionState extends State<OrdersSection> {
  late Future<List<Map<String, dynamic>>> _ordersFuture;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _ordersFuture = _loadOrders();
  }

  Future<List<Map<String, dynamic>>> _loadOrders() async {
    final rows = await Supabase.instance.client
        .from('orders')
        .select('id, reference, buyer_email, buyer_name, status, total_minor, currency, created_at, events(title)')
        .order('created_at', ascending: false)
        .limit(200);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> _refresh() async {
    setState(() => _ordersFuture = _loadOrders());
    await _ordersFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Orders', style: Theme.of(context).textTheme.headlineMedium),
              const Spacer(),
              SizedBox(
                width: 320,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search reference, email, event…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _search = value.toLowerCase()),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: 'Refresh'),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _ordersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Could not load orders: ${snapshot.error}'));
                }
                final orders = (snapshot.data ?? const [])
                    .where((o) => _search.isEmpty || _matches(o, _search))
                    .toList();
                if (orders.isEmpty) {
                  return const Center(child: Text('No orders match.'));
                }
                return ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) => _OrderRow(order: orders[index], onChanged: _refresh),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _matches(Map<String, dynamic> order, String query) {
    final eventTitle = (order['events'] as Map?)?['title'] as String? ?? '';
    return (order['reference'] as String? ?? '').toLowerCase().contains(query) ||
        (order['buyer_email'] as String? ?? '').toLowerCase().contains(query) ||
        eventTitle.toLowerCase().contains(query);
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order, required this.onChanged});

  final Map<String, dynamic> order;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String;
    final totalMinor = order['total_minor'] as int;
    final currency = order['currency'] as String? ?? 'GBP';
    final eventTitle = (order['events'] as Map?)?['title'] as String? ?? '(event deleted)';
    final canRefund = status == 'paid' || status == 'partially_refunded';

    return ListTile(
      title: Text('${order['reference']} — $eventTitle'),
      subtitle: Text('${order['buyer_email']} · ${order['created_at']}'),
      leading: _StatusChip(status: status),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            currency == 'GBP' ? '£${(totalMinor / 100).toStringAsFixed(2)}' : '$currency ${(totalMinor / 100).toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16),
          if (canRefund)
            OutlinedButton(
              onPressed: () => _showRefundDialog(context),
              child: const Text('Refund'),
            ),
        ],
      ),
    );
  }

  Future<void> _showRefundDialog(BuildContext context) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Refund ${order['reference']}?'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(labelText: 'Reason (kept in the audit log)'),
          autofocus: true,
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Refund')),
        ],
      ),
    );
    if (confirmed != true || reasonController.text.trim().isEmpty) return;

    try {
      await Supabase.instance.client.functions.invoke(
        'refund-order',
        body: {'order_id': order['id'], 'reason': reasonController.text.trim()},
      );
      onChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refund processed.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Refund failed: $e')));
      }
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (status) {
      'paid' => Colors.green,
      'pending' => Colors.orange,
      'refunded' || 'partially_refunded' => Colors.blueGrey,
      'failed' || 'cancelled' => Colors.red,
      _ => Colors.grey,
    };
    return Chip(
      label: Text(status, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}
