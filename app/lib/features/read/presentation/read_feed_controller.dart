import 'dart:async';

import 'package:flc_core/flc_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../read_providers.dart';

/// Stale-while-revalidate, same pattern as EventsFeedController: paint
/// instantly from the Drift cache, refresh in the background, only ever
/// show an error if there was nothing cached to fall back to.
class ReadFeedController extends AsyncNotifier<List<ArticleModel>> {
  @override
  Future<List<ArticleModel>> build() async {
    final repo = ref.watch(articlesRepositoryProvider);
    final cached = await repo.getCachedArticles();

    if (cached.isNotEmpty) {
      unawaited(refresh());
      return cached;
    }
    return repo.refreshArticles();
  }

  Future<void> refresh() async {
    final repo = ref.read(articlesRepositoryProvider);
    try {
      final fresh = await repo.refreshArticles();
      state = AsyncData(fresh);
    } catch (error, stackTrace) {
      final hadSomethingToShow = state.hasValue && state.value!.isNotEmpty;
      if (!hadSomethingToShow) {
        state = AsyncError(error, stackTrace);
      }
    }
  }
}

final AsyncNotifierProvider<ReadFeedController, List<ArticleModel>> readFeedControllerProvider =
    AsyncNotifierProvider<ReadFeedController, List<ArticleModel>>(ReadFeedController.new);
