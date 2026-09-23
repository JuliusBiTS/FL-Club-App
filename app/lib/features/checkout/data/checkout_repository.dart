import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

class CreateOrderResult {
  const CreateOrderResult({
    required this.orderId,
    required this.reference,
    required this.clientSecret,
    required this.totalMinor,
    required this.testMode,
  });

  final String orderId;
  final String reference;

  /// Null when [testMode] is true — there's no real PaymentIntent to
  /// confirm, see simulateTestPayment below.
  final String? clientSecret;
  final int totalMinor;

  /// True when the server has no Stripe secret key configured yet, so
  /// create-order skipped Stripe entirely rather than failing — lets the
  /// rest of the ticketing flow (order → paid → ticket issued →
  /// confirmation) be exercised end to end before a real Stripe account is
  /// connected. See docs/DECISIONS.md.
  final bool testMode;
}

/// The client never computes a price or creates an order row itself —
/// this just calls create-order and hands back whatever the server
/// decided (briefing §9.3 server flow, §8.2). Same for order status: the
/// app only ever reads it, via Realtime, never writes it directly.
class CheckoutRepository {
  CheckoutRepository(this._client);

  final SupabaseClient _client;

  Future<CreateOrderResult> createOrder({
    required String eventId,
    required String ticketTypeId,
    required int quantity,
    bool useLoyaltyReward = false,
    List<String>? attendeeNames,
  }) async {
    final response = await _client.functions.invoke(
      'create-order',
      body: {
        'event_id': eventId,
        'ticket_type_id': ticketTypeId,
        'quantity': quantity,
        'use_loyalty_reward': useLoyaltyReward,
        'attendee_names': ?attendeeNames,
      },
    );

    final data = response.data as Map<String, dynamic>;
    return CreateOrderResult(
      orderId: data['order_id'] as String,
      reference: data['reference'] as String,
      clientSecret: data['client_secret'] as String?,
      totalMinor: data['total_minor'] as int,
      testMode: data['test_mode'] as bool? ?? false,
    );
  }

  /// Only ever succeeds server-side when the club has NOT connected a real
  /// Stripe account — see simulate-test-payment's own guard. Marks the
  /// order paid exactly like a real webhook would, so ticket issuance,
  /// loyalty, and the confirmation screen all run for real.
  Future<void> simulateTestPayment(String orderId) async {
    await _client.functions.invoke('simulate-test-payment', body: {'order_id': orderId});
  }

  /// Streams the order's own row so the app can react the moment
  /// stripe-webhook flips it to 'paid' — the app never creates tickets
  /// itself (briefing §9.3 step 5).
  Stream<String> watchOrderStatus(String orderId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map((rows) => rows.isEmpty ? 'pending' : rows.first['status'] as String);
  }
}

final Provider<CheckoutRepository> checkoutRepositoryProvider = Provider<CheckoutRepository>((ref) {
  return CheckoutRepository(ref.watch(supabaseClientProvider));
});
