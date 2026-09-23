import 'package:flc_core/flc_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Talks to Supabase directly. RLS (supabase/migrations/20260817000009)
/// already restricts this to published events for anyone, draft+ for
/// staff/admin — this class does not need to duplicate that filtering
/// itself for security, only for correctness of what it asks for.
class EventsRemoteDataSource {
  EventsRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<List<EventModel>> fetchUpcomingPublished({int limit = 20, int offset = 0}) async {
    final rows = await _client
        .from('events')
        .select()
        .eq('status', 'published')
        .gte('starts_at', DateTime.now().toUtc().toIso8601String())
        .order('starts_at')
        .range(offset, offset + limit - 1);
    return rows.map(EventModel.fromJson).toList();
  }

  /// Most-recently-finished first — the standard "past events" order, and
  /// the same direction the admin console's own Past filter uses.
  Future<List<EventModel>> fetchPastPublished({int limit = 60}) async {
    final rows = await _client
        .from('events')
        .select()
        .eq('status', 'published')
        .lt('starts_at', DateTime.now().toUtc().toIso8601String())
        .order('starts_at', ascending: false)
        .limit(limit);
    return rows.map(EventModel.fromJson).toList();
  }

  Future<EventModel?> fetchBySlug(String slug) async {
    final row = await _client.from('events').select().eq('slug', slug).maybeSingle();
    if (row == null) return null;
    return EventModel.fromJson(row);
  }

  /// Ids of events that are 75%+ sold (derived in Postgres by
  /// events_selling_fast(); only ids leave the database, never counts).
  /// Failure is silent — a missing ribbon is better than a broken feed.
  Future<Set<String>> fetchSellingFastIds() async {
    try {
      final dynamic rows = await _client.rpc('events_selling_fast');
      return <String>{for (final dynamic id in (rows as List<dynamic>)) id as String};
    } catch (_) {
      return <String>{};
    }
  }

  /// Ids of events that are fully sold out (derived in Postgres by
  /// events_sold_out(); same reasoning as fetchSellingFastIds).
  Future<Set<String>> fetchSoldOutIds() async {
    try {
      final dynamic rows = await _client.rpc('events_sold_out');
      return <String>{for (final dynamic id in (rows as List<dynamic>)) id as String};
    } catch (_) {
      return <String>{};
    }
  }

  Future<List<TicketTypeModel>> fetchTicketTypes(String eventId) async {
    final rows = await _client
        .from('ticket_types')
        .select()
        .eq('event_id', eventId)
        .eq('is_active', true)
        .order('sort_order');
    return rows.map(TicketTypeModel.fromJson).toList();
  }
}
