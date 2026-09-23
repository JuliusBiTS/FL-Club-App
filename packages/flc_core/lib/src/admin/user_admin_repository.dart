import 'package:supabase_flutter/supabase_flutter.dart';

/// One person as the admin console sees them. Deliberately a plain class,
/// not ProfileModel: admins need fields (notes, sign-up date, source) that
/// the consumer app's own-profile model never carries.
class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.email,
    this.fullName,
    required this.role,
    required this.memberStatus,
    this.membershipKind,
    this.membershipNumber,
    this.membershipExpiresAt,
    this.notes,
    this.createdAt,
    this.marketingOptIn = false,
    this.registrationSource,
  });

  final String id;
  final String email;
  final String? fullName;

  /// 'user' | 'staff' | 'admin'
  final String role;

  /// 'none' | 'applied' | 'active' | 'lapsed' | 'suspended'
  final String memberStatus;

  /// 'full' | 'honorary' | 'lifetime' or null
  final String? membershipKind;
  final String? membershipNumber;
  final DateTime? membershipExpiresAt;
  final String? notes;
  final DateTime? createdAt;
  final bool marketingOptIn;
  final String? registrationSource;

  String get displayName => (fullName != null && fullName!.trim().isNotEmpty) ? fullName!.trim() : email;

  factory ManagedUser.fromRow(Map<String, dynamic> r) => ManagedUser(
        id: r['id'] as String,
        email: (r['email'] as String?) ?? '',
        fullName: r['full_name'] as String?,
        role: (r['role'] as String?) ?? 'user',
        memberStatus: (r['member_status'] as String?) ?? 'none',
        membershipKind: r['membership_kind'] as String?,
        membershipNumber: r['membership_number'] as String?,
        membershipExpiresAt: r['membership_expires_at'] == null ? null : DateTime.parse(r['membership_expires_at'] as String),
        notes: r['membership_notes'] as String?,
        createdAt: r['created_at'] == null ? null : DateTime.parse(r['created_at'] as String),
        marketingOptIn: (r['marketing_opt_in'] as bool?) ?? false,
        registrationSource: r['registration_source'] as String?,
      );
}

/// Which slice of people to list.
enum UserFilter { all, members, staff, applied }

/// Everything user/staff management needs. Reading relies on the admin RLS
/// policy on profiles; changes go through `admin_update_user`, which
/// re-checks admin in Postgres, refuses locking the club out of admin
/// access, and writes the audit log — the client only ever asks.
class UserAdminRepository {
  UserAdminRepository(this._client);

  final SupabaseClient _client;

  static const String _columns =
      'id, email, full_name, role, member_status, membership_kind, membership_number, '
      'membership_expires_at, membership_notes, created_at, marketing_opt_in, registration_source';

  Future<List<ManagedUser>> listUsers({String search = '', UserFilter filter = UserFilter.all, int limit = 100}) async {
    var query = _client.from('profiles').select(_columns).isFilter('deleted_at', null);

    switch (filter) {
      case UserFilter.all:
        break;
      case UserFilter.members:
        query = query.eq('member_status', 'active');
      case UserFilter.staff:
        query = query.inFilter('role', <String>['staff', 'admin']);
      case UserFilter.applied:
        query = query.eq('member_status', 'applied');
    }

    // PostgREST's or() syntax breaks on these characters — strip them
    // rather than let a stray comma in a search return an error.
    final String term = search.trim().replaceAll(RegExp(r'[,()%*\\]'), '');
    if (term.isNotEmpty) {
      query = query.or('email.ilike.%$term%,full_name.ilike.%$term%');
    }

    final rows = await query.order('created_at', ascending: false).limit(limit);
    return rows.map(ManagedUser.fromRow).toList();
  }

  Future<void> updateUser({
    required String userId,
    required String role,
    required String memberStatus,
    String? membershipKind,
    String? membershipNumber,
    DateTime? membershipExpiresAt,
    String? notes,
  }) async {
    await _client.rpc('admin_update_user', params: <String, dynamic>{
      'p_user_id': userId,
      'p_role': role,
      'p_member_status': memberStatus,
      'p_membership_kind': membershipKind,
      'p_membership_number': membershipNumber,
      'p_membership_expires_at': membershipExpiresAt?.toUtc().toIso8601String(),
      'p_notes': notes,
    });
  }
}
