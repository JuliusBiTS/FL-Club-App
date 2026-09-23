import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

/// The person's own picture, kept in a private bucket and only ever reached
/// through the `profile-photo` Edge Function (see its header for the security
/// model). The app never holds a permanent link — just a short-lived signed
/// URL that is re-requested when needed.
class ProfilePhotoRepository {
  ProfilePhotoRepository(this._client);

  final SupabaseClient _client;

  Future<String?> currentUrl() => _call(<String, dynamic>{'action': 'get'});

  Future<String?> upload(Uint8List bytes) => _call(<String, dynamic>{'action': 'set', 'image_base64': base64Encode(bytes)});

  Future<void> remove() async {
    await _call(<String, dynamic>{'action': 'remove'});
  }

  Future<String?> _call(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke('profile-photo', body: body);
      return (response.data as Map<String, dynamic>)['photo_signed_url'] as String?;
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map && details['error'] is String ? details['error'] as String : "Couldn't update your picture.";
      throw ProfilePhotoException(message);
    }
  }
}

class ProfilePhotoException implements Exception {
  ProfilePhotoException(this.message);
  final String message;
  @override
  String toString() => message;
}

final Provider<ProfilePhotoRepository> profilePhotoRepositoryProvider =
    Provider<ProfilePhotoRepository>((ref) => ProfilePhotoRepository(ref.watch(supabaseClientProvider)));

/// Signed URL of the current user's picture, or null. Invalidate after a change.
final FutureProvider<String?> profilePhotoUrlProvider = FutureProvider<String?>((ref) async {
  if (ref.watch(currentUserProvider) == null) return null;
  try {
    return await ref.watch(profilePhotoRepositoryProvider).currentUrl();
  } catch (_) {
    return null; // an avatar is decoration — never let it break the screen
  }
});
