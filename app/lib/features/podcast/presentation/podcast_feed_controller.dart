import 'dart:async';

import 'package:flc_core/flc_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../podcast_providers.dart';

/// Stale-while-revalidate, same pattern as EventsFeedController.
class PodcastFeedController extends AsyncNotifier<List<PodcastEpisodeModel>> {
  @override
  Future<List<PodcastEpisodeModel>> build() async {
    final repo = ref.watch(podcastRepositoryProvider);
    final cached = await repo.getCachedEpisodes();

    if (cached.isNotEmpty) {
      unawaited(refresh());
      return cached;
    }
    return repo.refreshEpisodes();
  }

  Future<void> refresh() async {
    final repo = ref.read(podcastRepositoryProvider);
    try {
      final fresh = await repo.refreshEpisodes();
      state = AsyncData(fresh);
    } catch (error, stackTrace) {
      final hadSomethingToShow = state.hasValue && state.value!.isNotEmpty;
      if (!hadSomethingToShow) {
        state = AsyncError(error, stackTrace);
      }
    }
  }
}

final AsyncNotifierProvider<PodcastFeedController, List<PodcastEpisodeModel>> podcastFeedControllerProvider =
    AsyncNotifierProvider<PodcastFeedController, List<PodcastEpisodeModel>>(PodcastFeedController.new);
