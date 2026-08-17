import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

class CreateOrderResult {
  const CreateOrderResult({
    required this.orderId,
    required this.reference,
    required this.clientSecret,
    required this.totalMinor,
  });

  final String orderId;
  final String reference;
  final String clientSecret;
  final int totalMinor;
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
      clientSecret: data['client_secret'] as String,
      totalMinor: data['total_minor'] as int,
    );
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
