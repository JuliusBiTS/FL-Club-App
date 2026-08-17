import 'package:flc_core/flc_core.dart';

/// The only thing controllers/widgets are allowed to depend on for event
/// data — briefing §7.3: "presentation -> controller -> repository ->
/// data source (remote | local). No Supabase calls inside widgets, ever."
abstract class EventsRepository {
  Future<List<EventModel>> getCachedUpcoming();

  /// Hits the network, writes the result to the local cache, and returns
  /// it. Throws on failure — callers decide how to degrade (briefing §7.3:
  /// "failures are surfaced clearly, never silently swallowed").
  Future<List<EventModel>> refreshUpcoming();

  Future<EventModel?> getEventDetail(String slug, {bool forceRefresh = false});

  Future<List<TicketTypeModel>> getTicketTypes(String eventId);
}
