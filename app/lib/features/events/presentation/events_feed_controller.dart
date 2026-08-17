import 'dart:async';

import 'package:flc_core/flc_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../events_providers.dart';

/// Stale-while-revalidate: paints instantly from the Drift cache if there
/// is one, kicks off a network refresh in the background, and only ever
/// replaces already-shown data with an error if there was nothing cached
/// to fall back to (briefing §7.3 offline-first rule + §9.1 "Offline =
/// cached list plus a top banner").
class EventsFeedController extends AsyncNotifier<List<EventModel>> {
  @override
  Future<List<EventModel>> build() async {
    final repo = ref.watch(eventsRepositoryProvider);
    final cached = await repo.getCachedUpcoming();

    if (cached.isNotEmpty) {
      unawaited(refresh());
      return cached;
    }
    return repo.refreshUpcoming();
  }

  Future<void> refresh() async {
    final repo = ref.read(eventsRepositoryProvider);
    try {
      final fresh = await repo.refreshUpcoming();
      state = AsyncData(fresh);
    } catch (error, stackTrace) {
      final hadSomethingToShow = state.hasValue && state.value!.isNotEmpty;
      if (!hadSomethingToShow) {
        state = AsyncError(error, stackTrace);
      }
      // else: keep showing the cached list; the feed screen is responsible
      // for surfacing a "showing saved events" banner via a separate
      // isStale/lastSyncedAt signal if/when that's wired up.
    }
  }
}

final AsyncNotifierProvider<EventsFeedController, List<EventModel>> eventsFeedControllerProvider =
    AsyncNotifierProvider<EventsFeedController, List<EventModel>>(EventsFeedController.new);
