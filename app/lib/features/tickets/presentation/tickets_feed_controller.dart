import 'dart:async';

import 'package:flc_core/flc_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tickets_providers.dart';

/// Same stale-while-revalidate shape as events_feed_controller.dart —
/// paint instantly from the Drift cache, refresh in the background, and
/// only surface an error if there was nothing cached to fall back to.
class TicketsFeedController extends AsyncNotifier<List<TicketModel>> {
  @override
  Future<List<TicketModel>> build() async {
    final repo = ref.watch(ticketsRepositoryProvider);
    final cached = await repo.getCachedTickets();

    if (cached.isNotEmpty) {
      unawaited(refresh());
      return cached;
    }
    return repo.refreshTickets();
  }

  Future<void> refresh() async {
    final repo = ref.read(ticketsRepositoryProvider);
    try {
      final fresh = await repo.refreshTickets();
      state = AsyncData(fresh);
    } catch (error, stackTrace) {
      final hadSomethingToShow = state.hasValue && state.value!.isNotEmpty;
      if (!hadSomethingToShow) {
        state = AsyncError(error, stackTrace);
      }
    }
  }
}

final AsyncNotifierProvider<TicketsFeedController, List<TicketModel>> ticketsFeedControllerProvider =
    AsyncNotifierProvider<TicketsFeedController, List<TicketModel>>(TicketsFeedController.new);
