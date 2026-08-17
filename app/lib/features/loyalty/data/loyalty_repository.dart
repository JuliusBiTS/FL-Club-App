import 'package:flc_core/flc_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Everything here is a direct Supabase read — RLS already scopes
/// loyalty_ledger/loyalty_rewards to their owner (or staff), and
/// loyalty_config is publicly readable, so none of this needs an Edge
/// Function (unlike get-member-card, which exists only because it signs
/// something). loyalty_balances is a view, never computed client-side —
/// see its own comment in the migration: "the only place a loyalty
/// balance is computed."
class LoyaltyRepository {
  LoyaltyRepository(this._client);

  final SupabaseClient _client;

  Future<int> getBalance(String userId) async {
    final row =
        await _client.from('loyalty_balances').select('balance').eq('user_id', userId).maybeSingle();
    return (row?['balance'] as int?) ?? 0;
  }

  Future<LoyaltyConfigModel> getConfig() async {
    final row = await _client.from('loyalty_config').select().eq('id', 1).single();
    return LoyaltyConfigModel.fromJson(row);
  }

  Future<List<LoyaltyRewardModel>> getRewards(String userId) async {
    final rows = await _client
        .from('loyalty_rewards')
        .select()
        .eq('user_id', userId)
        .order('earned_at', ascending: false);
    return (rows as List<dynamic>)
        .map((r) => LoyaltyRewardModel.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<LoyaltyLedgerEntryModel>> getLedger(String userId) async {
    final rows = await _client
        .from('loyalty_ledger')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (rows as List<dynamic>)
        .map((r) => LoyaltyLedgerEntryModel.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Just the count checkout needs to decide whether to show the "use
  /// your free ticket" toggle at all — cheaper than fetching every reward
  /// with its full detail on a screen that only needs a yes/no.
  Future<int> availableRewardCount(String userId) async {
    final rows =
        await _client.from('loyalty_rewards').select('id').eq('user_id', userId).eq('status', 'available');
    return (rows as List<dynamic>).length;
  }

  /// The ledger only stores event_id (briefing §9.5: "the ledger view
  /// groups by event, never by ticket") — this resolves the titles for
  /// display in one batch query rather than N+1.
  Future<Map<String, String>> eventTitlesFor(Iterable<String> eventIds) async {
    final ids = eventIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await _client.from('events').select('id, title').inFilter('id', ids);
    return {for (final r in rows as List<dynamic>) (r as Map<String, dynamic>)['id'] as String: r['title'] as String};
  }
}
