import 'package:flc_core/flc_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import 'data/media_repository.dart';

final Provider<MediaRepository> mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(ref.watch(supabaseClientProvider));
});

final AsyncNotifierProvider<MediaFeedController, List<MediaPostModel>> mediaFeedControllerProvider =
    AsyncNotifierProvider<MediaFeedController, List<MediaPostModel>>(MediaFeedController.new);

class MediaFeedController extends AsyncNotifier<List<MediaPostModel>> {
  @override
  Future<List<MediaPostModel>> build() {
    return ref.watch(mediaRepositoryProvider).getPosts();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => ref.read(mediaRepositoryProvider).getPosts());
  }
}
