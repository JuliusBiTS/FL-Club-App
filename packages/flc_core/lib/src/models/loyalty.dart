import 'package:freezed_annotation/freezed_annotation.dart';

part 'loyalty.freezed.dart';
part 'loyalty.g.dart';

/// Mirrors `loyalty_ledger` (supabase/migrations/20260817000005). Read
/// directly via the Supabase client — RLS already scopes every row to its
/// owner (or staff), no Edge Function needed. Never sum these client-side
/// for a balance; always read `loyalty_balances` instead (§ the view's own
/// comment: "the only place a loyalty balance is computed").
@freezed
abstract class LoyaltyLedgerEntryModel with _$LoyaltyLedgerEntryModel {
  const factory LoyaltyLedgerEntryModel({
    required String id,
    @JsonKey(name: 'user_id') required String userId,
    required int delta,
    required String reason,
    @JsonKey(name: 'ticket_id') String? ticketId,
    @JsonKey(name: 'event_id') String? eventId,
    String? note,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _LoyaltyLedgerEntryModel;

  factory LoyaltyLedgerEntryModel.fromJson(Map<String, dynamic> json) =>
      _$LoyaltyLedgerEntryModelFromJson(json);
}

/// Mirrors `loyalty_rewards`. A `status: 'available'` row is what
/// checkout's "use your free ticket" toggle checks for.
@freezed
abstract class LoyaltyRewardModel with _$LoyaltyRewardModel {
  const factory LoyaltyRewardModel({
    required String id,
    @JsonKey(name: 'user_id') required String userId,
    @Default('available') String status,
    @JsonKey(name: 'earned_at') required DateTime earnedAt,
    @JsonKey(name: 'expires_at') DateTime? expiresAt,
    @JsonKey(name: 'reserved_order_id') String? reservedOrderId,
    @JsonKey(name: 'redeemed_order_id') String? redeemedOrderId,
    @JsonKey(name: 'redeemed_at') DateTime? redeemedAt,
  }) = _LoyaltyRewardModel;

  const LoyaltyRewardModel._();

  factory LoyaltyRewardModel.fromJson(Map<String, dynamic> json) => _$LoyaltyRewardModelFromJson(json);

  bool get isAvailable => status == 'available';
}

/// Mirrors the `loyalty_config` singleton row (id=1) — publicly readable
/// (no auth required), so the "buy N get 1 free" rule can be shown even
/// signed out. `countMode` is 'purchased' or 'attended'; only one is ever
/// live at a time server-side (briefing §10.1).
@freezed
abstract class LoyaltyConfigModel with _$LoyaltyConfigModel {
  const factory LoyaltyConfigModel({
    @Default(10) int threshold,
    @JsonKey(name: 'count_mode') @Default('purchased') String countMode,
    @JsonKey(name: 'min_price_minor') @Default(1) int minPriceMinor,
    @JsonKey(name: 'member_tickets_count') @Default(true) bool memberTicketsCount,
    @JsonKey(name: 'max_points_per_event') @Default(1) int maxPointsPerEvent,
    @JsonKey(name: 'reward_expiry_months') int? rewardExpiryMonths,
  }) = _LoyaltyConfigModel;

  factory LoyaltyConfigModel.fromJson(Map<String, dynamic> json) => _$LoyaltyConfigModelFromJson(json);
}
