import 'package:flc_core/flc_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Membership verification is online-only in v1 (briefing §9.11 —
/// "checked at leisure at a desk", not a door queue under time pressure),
/// so unlike DoorScanRepository this always calls verify-scan directly.
class MembershipScanRepository {
  MembershipScanRepository(this._client);

  final SupabaseClient _client;

  Future<MembershipScanResultModel> scanQr({required String payload, required String deviceId}) async {
    final response = await _client.functions.invoke(
      'verify-scan',
      body: {'kind': 'membership', 'device_id': deviceId, 'manual': false, 'payload': payload},
    );
    return MembershipScanResultModel.fromApiJson(response.data as Map<String, dynamic>);
  }

  Future<MembershipScanResultModel> lookupManual({required String membershipNumber, required String deviceId}) async {
    final response = await _client.functions.invoke(
      'verify-scan',
      body: {'kind': 'membership', 'device_id': deviceId, 'manual': true, 'membership_number': membershipNumber},
    );
    return MembershipScanResultModel.fromApiJson(response.data as Map<String, dynamic>);
  }
}
