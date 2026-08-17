import 'package:flc_core/flc_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import 'data/loyalty_repository.dart';

final Provider<LoyaltyRepository> loyaltyRepositoryProvider = Provider<LoyaltyRepository>((ref) {
  return LoyaltyRepository(ref.watch(supabaseClientProvider));
});

/// Everything the loyalty screen needs in one bundle, so it can show
/// balance/progress, rewards, and the event-grouped ledger without
/// juggling four separate loading states.
class LoyaltyStatus {
  const LoyaltyStatus({
    required this.balance,
    required this.config,
    required this.rewards,
    required this.ledger,
    required this.eventTitles,
  });

  final int balance;
  final LoyaltyConfigModel config;
  final List<LoyaltyRewardModel> rewards;
  final List<LoyaltyLedgerEntryModel> ledger;
  final Map<String, String> eventTitles;
}

final FutureProvider<LoyaltyStatus?> loyaltyStatusProvider = FutureProvider<LoyaltyStatus?>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return null;

  final repo = ref.watch(loyaltyRepositoryProvider);
  final results = await Future.wait([
    repo.getBalance(userId),
    repo.getConfig(),
    repo.getRewards(userId),
    repo.getLedger(userId),
  ]);
  final balance = results[0] as int;
  final config = results[1] as LoyaltyConfigModel;
  final rewards = results[2] as List<LoyaltyRewardModel>;
  final ledger = results[3] as List<LoyaltyLedgerEntryModel>;

  final eventTitles = await repo.eventTitlesFor(ledger.map((e) => e.eventId).nonNulls);

  return LoyaltyStatus(balance: balance, config: config, rewards: rewards, ledger: ledger, eventTitles: eventTitles);
});

/// Lightweight — checkout only needs a yes/no on whether to show the "use
/// your free ticket" toggle, not the full status bundle above.
final AutoDisposeFutureProvider<int> availableRewardCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return 0;
  return ref.watch(loyaltyRepositoryProvider).availableRewardCount(userId);
});
