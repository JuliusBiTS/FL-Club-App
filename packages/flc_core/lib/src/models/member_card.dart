import 'package:freezed_annotation/freezed_annotation.dart';

part 'member_card.freezed.dart';

/// Shaped from supabase/functions/get-member-card's response — briefing
/// §9.6/§13.4. Deliberately separate from ProfileModel: `membershipPin`
/// and `photoSignedUrl` only ever arrive through this call, never a
/// general profile read (§13.6). `memberSecret` is base64url-encoded,
/// already scoped server-side to `period` — decode it once and feed it to
/// `currentMemberPayload()` to mint the rotating QR locally from then on.
@freezed
abstract class MemberCardModel with _$MemberCardModel {
  const factory MemberCardModel({
    required String fullName,
    String? membershipKind,
    String? membershipNumber,
    String? membershipPin,
    DateTime? memberSince,
    DateTime? validTo,
    String? photoSignedUrl,
    required String memberSecret,
    required String period,
  }) = _MemberCardModel;

  const MemberCardModel._();

  factory MemberCardModel.fromApiJson(Map<String, dynamic> json) => MemberCardModel(
        fullName: json['full_name'] as String? ?? 'Member',
        membershipKind: json['membership_kind'] as String?,
        membershipNumber: json['membership_number'] as String?,
        membershipPin: json['membership_pin'] as String?,
        memberSince: json['member_since'] == null ? null : DateTime.parse(json['member_since'] as String),
        validTo: json['valid_to'] == null ? null : DateTime.parse(json['valid_to'] as String),
        photoSignedUrl: json['photo_signed_url'] as String?,
        memberSecret: json['member_secret'] as String,
        period: json['period'] as String,
      );

  /// Flat round-trip for the secure-storage cache — excludes
  /// `photoSignedUrl` on purpose, it's a 15-minute signed URL and useless
  /// once stale; the photo itself is cached separately as a local file.
  Map<String, dynamic> toCacheJson() => <String, dynamic>{
        'fullName': fullName,
        'membershipKind': membershipKind,
        'membershipNumber': membershipNumber,
        'membershipPin': membershipPin,
        'memberSince': memberSince?.toIso8601String(),
        'validTo': validTo?.toIso8601String(),
        'memberSecret': memberSecret,
        'period': period,
      };

  factory MemberCardModel.fromCacheJson(Map<String, dynamic> json) => MemberCardModel(
        fullName: json['fullName'] as String,
        membershipKind: json['membershipKind'] as String?,
        membershipNumber: json['membershipNumber'] as String?,
        membershipPin: json['membershipPin'] as String?,
        memberSince: json['memberSince'] == null ? null : DateTime.parse(json['memberSince'] as String),
        validTo: json['validTo'] == null ? null : DateTime.parse(json['validTo'] as String),
        memberSecret: json['memberSecret'] as String,
        period: json['period'] as String,
      );
}
