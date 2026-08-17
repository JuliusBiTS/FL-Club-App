import 'package:freezed_annotation/freezed_annotation.dart';

part 'ticket_type.freezed.dart';
part 'ticket_type.g.dart';

/// Mirrors `ticket_types` (supabase/migrations/20260817000003). This is the
/// ONLY source of truth for a price the app ever displays — briefing §8.2:
/// "never hard-code a price anywhere", "no client-side price arithmetic
/// beyond price × quantity".
@freezed
class TicketTypeModel with _$TicketTypeModel {
  const factory TicketTypeModel({
    required String id,
    @JsonKey(name: 'event_id') required String eventId,
    required String name,
    String? description,
    @Default('public') String audience,
    @JsonKey(name: 'price_minor') required int priceMinor,
    @Default('GBP') String currency,
    required int quantity,
    @JsonKey(name: 'max_per_order') @Default(4) int maxPerOrder,
    @JsonKey(name: 'requires_member') @Default(false) bool requiresMember,
    @JsonKey(name: 'requires_proof') @Default(false) bool requiresProof,
    @JsonKey(name: 'sales_start_at') DateTime? salesStartAt,
    @JsonKey(name: 'sales_end_at') DateTime? salesEndAt,
    @JsonKey(name: 'is_active') @Default(true) bool isActive,
  }) = _TicketTypeModel;

  factory TicketTypeModel.fromJson(Map<String, dynamic> json) => _$TicketTypeModelFromJson(json);
}

extension TicketTypeModelDisplay on TicketTypeModel {
  /// £-formatted display string. The ONLY place price formatting happens —
  /// route every screen through this rather than re-deriving it.
  String get priceDisplay => priceMinor == 0 ? 'Free' : '£${(priceMinor / 100).toStringAsFixed(2)}';

  bool get onSale {
    final now = DateTime.now().toUtc();
    if (salesStartAt != null && now.isBefore(salesStartAt!.toUtc())) return false;
    if (salesEndAt != null && now.isAfter(salesEndAt!.toUtc())) return false;
    return isActive;
  }
}
