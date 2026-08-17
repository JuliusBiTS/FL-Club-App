import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/supabase/supabase_providers.dart';
import 'data/member_card_repository.dart';
import 'data/member_card_store.dart';
import 'data/member_photo_cache.dart';

final Provider<MemberCardStore> memberCardStoreProvider = Provider<MemberCardStore>((ref) {
  return MemberCardStore(const FlutterSecureStorage());
});

final Provider<MemberPhotoCache> memberPhotoCacheProvider = Provider<MemberPhotoCache>((ref) {
  return MemberPhotoCache();
});

final Provider<MemberCardRepository> memberCardRepositoryProvider = Provider<MemberCardRepository>((ref) {
  return MemberCardRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(memberCardStoreProvider),
    ref.watch(memberPhotoCacheProvider),
  );
});
