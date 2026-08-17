import 'package:flc_core/flc_core.dart';

import '../domain/events_repository.dart';
import 'events_local_data_source.dart';
import 'events_remote_data_source.dart';

class EventsRepositoryImpl implements EventsRepository {
  EventsRepositoryImpl(this._remote, this._local);

  final EventsRemoteDataSource _remote;
  final EventsLocalDataSource _local;

  @override
  Future<List<EventModel>> getCachedUpcoming() => _local.readCachedUpcoming();

  @override
  Future<List<EventModel>> refreshUpcoming() async {
    final fresh = await _remote.fetchUpcomingPublished();
    await _local.writeEvents(fresh);
    return fresh;
  }

  @override
  Future<EventModel?> getEventDetail(String slug, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await _local.readCachedBySlug(slug);
      if (cached != null) return cached;
    }
    final fresh = await _remote.fetchBySlug(slug);
    if (fresh != null) {
      await _local.writeEvents([fresh]);
    }
    return fresh;
  }

  @override
  Future<List<TicketTypeModel>> getTicketTypes(String eventId) => _remote.fetchTicketTypes(eventId);
}
