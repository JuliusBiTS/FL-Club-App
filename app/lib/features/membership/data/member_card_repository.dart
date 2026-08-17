import 'package:flc_core/flc_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'member_card_store.dart';
import 'member_photo_cache.dart';

/// Friendly text for whatever get-member-card's errorResponse sent back
/// ({ error, details }) — same pattern as scanFunctionErrorMessage in the
/// scanner feature, kept local rather than shared since each Edge
/// Function's error copy is feature-specific anyway.
String memberCardErrorMessage(Object error) {
  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] is String) return details['error'] as String;
  }
  return 'Something went wrong. Please try again.';
}

class MemberCardRepository {
  MemberCardRepository(this._client, this._store, this._photoCache);

  final SupabaseClient _client;
  final MemberCardStore _store;
  final MemberPhotoCache _photoCache;

  Future<MemberCardModel> refresh() async {
    final response = await _client.functions.invoke('get-member-card');
    final data = response.data as Map<String, dynamic>;
    final card = MemberCardModel.fromApiJson(data);

    await _store.save(card);
    final photoUrl = data['photo_signed_url'] as String?;
    if (photoUrl != null) {
      await _photoCache.downloadAndSave(photoUrl);
    }
    return card;
  }

  Future<MemberCardModel?> getCached() => _store.read();

  Future<String?> cachedPhotoPath() async => (await _photoCache.cached())?.path;
}
