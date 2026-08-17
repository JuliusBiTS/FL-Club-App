import 'package:freezed_annotation/freezed_annotation.dart';

part 'scan_result.freezed.dart';

/// One item of verify-scan's ticket-batch response. `result` is the raw
/// `scan_result` Postgres enum value ('valid', 'already_redeemed',
/// 'invalid_signature', 'expired_code', 'not_found', 'wrong_event',
/// 'ticket_refunded') — kept as a string rather than a Dart enum so a
/// server-added enum value never breaks deserialisation client-side.
@freezed
abstract class TicketScanResultModel with _$TicketScanResultModel {
  const factory TicketScanResultModel({
    required String ticketId,
    required String result,
    String? attendeeName,
    String? ticketTypeName,
    String? redeemedAt,
    String? redeemedBy,
  }) = _TicketScanResultModel;

  factory TicketScanResultModel.fromApiJson(Map<String, dynamic> json) => TicketScanResultModel(
        ticketId: json['ticket_id'] as String,
        result: json['result'] as String,
        attendeeName: json['attendee_name'] as String?,
        ticketTypeName: json['ticket_type_name'] as String?,
        redeemedAt: json['redeemed_at'] as String?,
        redeemedBy: json['redeemed_by'] as String?,
      );
}

extension TicketScanResultModelDisplay on TicketScanResultModel {
  bool get isValid => result == 'valid';
  bool get isAlreadyRedeemed => result == 'already_redeemed';
}

/// verify-scan's membership response. `authenticated` is the three-tier
/// trust distinction from briefing §9.11/DECISIONS.md: false means the
/// membership number matched (tier 1, "identification" — a username, not
/// a password) but the rotating signed QR was never checked; true means
/// the HMAC signature verified (tier 2, "authentication"). Staff still
/// have to eyeball `photoSignedUrl` against the person in front of them
/// for tier 3 ("verification of person") before honouring a member
/// price — the UI must never present an `authenticated: false` result as
/// equivalent to a verified member.
@freezed
abstract class MembershipScanResultModel with _$MembershipScanResultModel {
  const factory MembershipScanResultModel({
    required String result,
    String? profileId,
    required bool authenticated,
    String? fullName,
    String? membershipKind,
    String? validTo,
    String? photoSignedUrl,
  }) = _MembershipScanResultModel;

  factory MembershipScanResultModel.fromApiJson(Map<String, dynamic> json) => MembershipScanResultModel(
        result: json['result'] as String,
        profileId: json['profile_id'] as String?,
        authenticated: json['authenticated'] as bool? ?? false,
        fullName: json['full_name'] as String?,
        membershipKind: json['membership_kind'] as String?,
        validTo: json['valid_to'] as String?,
        photoSignedUrl: json['photo_signed_url'] as String?,
      );
}

extension MembershipScanResultModelDisplay on MembershipScanResultModel {
  bool get isValid => result == 'valid';
}
