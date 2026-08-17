import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

enum UserRole { user, staff, admin }

enum MemberStatus { none, applied, active, lapsed, suspended }

enum MembershipKind { full, honorary, lifetime }

/// The caller's OWN profile, as returned by Supabase (RLS restricts every
/// row to the owner or an admin — see supabase/migrations/20260817000009).
/// Deliberately does NOT include membership_pin or membership_photo_path:
/// those are only ever handed to the client inside the get-member-card /
/// verify-scan Edge Function responses, never through a general profile
/// read (briefing §13.6).
@freezed
class ProfileModel with _$ProfileModel {
  const factory ProfileModel({
    required String id,
    required String email,
    @JsonKey(name: 'full_name') String? fullName,
    @JsonKey(name: 'display_name') String? displayName,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    @Default(UserRole.user) UserRole role,
    @JsonKey(name: 'member_status') @Default(MemberStatus.none) MemberStatus memberStatus,
    @JsonKey(name: 'membership_kind') MembershipKind? membershipKind,
    @JsonKey(name: 'membership_number') String? membershipNumber,
    @JsonKey(name: 'membership_started_at') DateTime? membershipStartedAt,
    @JsonKey(name: 'membership_expires_at') DateTime? membershipExpiresAt,
    @JsonKey(name: 'marketing_opt_in') @Default(false) bool marketingOptIn,
    @JsonKey(name: 'push_opt_in') @Default(false) bool pushOptIn,
  }) = _ProfileModel;

  factory ProfileModel.fromJson(Map<String, dynamic> json) => _$ProfileModelFromJson(json);
}

extension ProfileModelAccess on ProfileModel {
  bool get isStaff => role == UserRole.staff || role == UserRole.admin;
  bool get isAdmin => role == UserRole.admin;

  /// This is a UX convenience check ONLY — never trust it to gate a
  /// purchase or reveal member-only content server-side. Every privileged
  /// decision is re-verified in Postgres RLS / an Edge Function regardless
  /// (briefing §7.3: client-side role checks are for UX only).
  bool get isActiveMember {
    if (memberStatus != MemberStatus.active) return false;
    if (membershipExpiresAt == null) return true; // lifetime/honorary
    return membershipExpiresAt!.isAfter(DateTime.now());
  }
}
