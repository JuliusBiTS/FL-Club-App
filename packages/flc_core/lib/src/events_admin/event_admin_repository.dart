import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/event.dart';
import '../models/ticket_type.dart';
import '../util/event_text.dart';
import 'event_draft.dart';

/// A failure already phrased for a person to read (briefing §16.4 tone).
class EventAdminException implements Exception {
  EventAdminException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CancelResult {
  const CancelResult({this.refunded = 0, this.failures = const <String>[]});

  final int refunded;
  final List<String> failures;
}

class PushResult {
  const PushResult({required this.recipients, this.delivered = 0, this.failed = 0, this.preview = false});

  final int recipients;
  final int delivered;
  final int failed;

  /// True when nothing was sent and [recipients] is just the audience size.
  final bool preview;
}

/// Everything the event editor needs from Supabase, in one place. Used by
/// both the admin console and the app's staff editor. Authorisation is NOT
/// decided here: staff/admin limits are enforced by Postgres (RLS + the
/// guard triggers in 20260921000001) and by the Edge Functions — this class
/// only turns their errors into plain English.
class EventAdminRepository {
  EventAdminRepository(this._client);

  final SupabaseClient _client;

  static const String _imageBucket = 'event-images';
  static const Set<String> _notCountedTicketStatuses = <String>{'void', 'cancelled', 'refunded'};

  /// Turns a low-level exception into something a producer can act on.
  static String describeError(Object error) {
    if (error is EventAdminException) return error.message;
    if (error is PostgrestException) {
      final String m = error.message;
      if (m.contains('row-level security') || error.code == '42501') {
        return 'You don\'t have permission to do that. Ask an admin.';
      }
      if (error.code == '23505' && m.contains('slug')) return 'Another event already uses that web address.';
      if (error.code == '23503') return 'That can\'t be removed because tickets or orders depend on it.';
      // Our own `raise exception '…'` messages are already written for people.
      return m;
    }
    if (error is StorageException) {
      return 'The picture couldn\'t be uploaded (${error.message}).';
    }
    if (error is FunctionException) {
      final Object? details = error.details;
      if (details is Map && details['error'] is String) return details['error'] as String;
      return 'The server couldn\'t complete that (${error.status}).';
    }
    return 'Something went wrong: $error';
  }

  // ---------------------------------------------------------------- reading

  Future<List<EventModel>> listEvents() async {
    final rows = await _client.from('events').select().order('starts_at', ascending: false).limit(300);
    return rows.map(EventModel.fromJson).toList();
  }

  /// Event ids currently flagged "selling fast" (derived in Postgres).
  Future<Set<String>> sellingFastIds() async {
    try {
      final dynamic rows = await _client.rpc('events_selling_fast');
      return <String>{for (final dynamic id in (rows as List<dynamic>)) id as String};
    } catch (_) {
      return <String>{};
    }
  }

  /// The club's default ticket rows (Standard / Member / Concession) — held in
  /// the database so no price is hard-coded in the app.
  Future<List<TicketTypeDraft>> defaultTicketTemplate() async {
    try {
      final Map<String, dynamic>? row =
          await _client.from('club_settings').select('default_ticket_template').maybeSingle();
      final List<dynamic> template = (row?['default_ticket_template'] as List<dynamic>?) ?? const <dynamic>[];
      return template.map((dynamic t) => TicketTypeDraft.fromTemplate(t as Map<String, dynamic>)).toList();
    } catch (_) {
      return <TicketTypeDraft>[];
    }
  }

  Future<EventDraft> loadDraft(String eventId) async {
    final Map<String, dynamic> eventRow = await _client.from('events').select().eq('id', eventId).single();
    final typeRows = await _client.from('ticket_types').select().eq('event_id', eventId).order('sort_order');
    final ticketRows = await _client.from('tickets').select('ticket_type_id, status').eq('event_id', eventId);

    final Map<String, int> soldByType = <String, int>{};
    for (final Map<String, dynamic> t in ticketRows) {
      if (_notCountedTicketStatuses.contains(t['status'])) continue;
      final String typeId = t['ticket_type_id'] as String;
      soldByType[typeId] = (soldByType[typeId] ?? 0) + 1;
    }

    return EventDraft.fromModel(
      EventModel.fromJson(eventRow),
      typeRows.map(TicketTypeModel.fromJson).toList(),
      soldByType: soldByType,
    );
  }

  // ---------------------------------------------------------------- writing

  /// Creates or updates the event and its ticket types. Returns the event id.
  /// [status] is what the event should be after this save ('draft',
  /// 'published', 'postponed', …).
  Future<String> save(EventDraft draft, {required String status}) async {
    final Map<String, dynamic> row = draft.toEventRow(forStatus: status);
    final String eventId;

    if (draft.id == null) {
      eventId = await _insertWithUniqueSlug(draft, row);
    } else {
      final updated = await _client.from('events').update(row).eq('id', draft.id!).select('id');
      if (updated.isEmpty) {
        throw EventAdminException('You don\'t have permission to change this event. Ask an admin.');
      }
      eventId = draft.id!;
    }

    await _saveTicketTypes(eventId, draft);
    return eventId;
  }

  Future<String> _insertWithUniqueSlug(EventDraft draft, Map<String, dynamic> row) async {
    final String base = EventText.slugify(draft.title, draft.startsAt);
    for (int attempt = 0; attempt < 6; attempt++) {
      final String slug = attempt == 0 ? base : '$base-${attempt + 1}';
      try {
        final Map<String, dynamic> inserted =
            await _client.from('events').insert(<String, dynamic>{...row, 'slug': slug}).select('id').single();
        return inserted['id'] as String;
      } on PostgrestException catch (e) {
        if (e.code == '23505' && e.message.contains('slug')) continue; // taken — try the next suffix
        rethrow;
      }
    }
    throw EventAdminException('Couldn\'t find a free web address for this event — try a slightly different title.');
  }

  Future<void> _saveTicketTypes(String eventId, EventDraft draft) async {
    final existing = await _client.from('ticket_types').select('id').eq('event_id', eventId);
    final Set<String> keptIds = <String>{for (final TicketTypeDraft t in draft.ticketTypes) if (t.id != null) t.id!};

    for (final Map<String, dynamic> e in existing) {
      final String id = e['id'] as String;
      if (keptIds.contains(id)) continue;
      try {
        await _client.from('ticket_types').delete().eq('id', id);
      } on PostgrestException catch (e) {
        if (e.code != '23503') rethrow;
        // Tickets exist against it, so it can't be deleted — withdraw it from sale instead.
        await _client.from('ticket_types').update(<String, dynamic>{'is_active': false}).eq('id', id);
      }
    }

    for (int i = 0; i < draft.ticketTypes.length; i++) {
      final TicketTypeDraft t = draft.ticketTypes[i];
      final Map<String, dynamic> row = t.toRow(eventId: eventId, sortOrder: i);
      if (t.id == null) {
        final Map<String, dynamic> inserted = await _client.from('ticket_types').insert(row).select('id').single();
        t.id = inserted['id'] as String;
      } else {
        await _client.from('ticket_types').update(row).eq('id', t.id!);
      }
    }
  }

  Future<void> setStatus(String eventId, String status) async {
    final updated = await _client.from('events').update(<String, dynamic>{'status': status}).eq('id', eventId).select('id');
    if (updated.isEmpty) throw EventAdminException('You don\'t have permission to change this event. Ask an admin.');
  }

  /// Only works for events with no orders (enforced in Postgres) and only for admins.
  Future<void> deleteEvent(String eventId) async {
    final deleted = await _client.from('events').delete().eq('id', eventId).select('id');
    if (deleted.isEmpty) throw EventAdminException('Only an admin can delete an event.');
  }

  /// Marks the event cancelled (admin only) and, if asked, refunds every paid
  /// order through the existing `refund-order` function (which also reverses
  /// loyalty points and writes the audit trail).
  Future<CancelResult> cancelEvent(String eventId, {required bool refundOrders}) async {
    await setStatus(eventId, 'cancelled');
    if (!refundOrders) return const CancelResult();

    final orders = await _client
        .from('orders')
        .select('id, reference')
        .eq('event_id', eventId)
        .inFilter('status', <String>['paid', 'partially_refunded']);

    int refunded = 0;
    final List<String> failures = <String>[];
    for (final Map<String, dynamic> o in orders) {
      try {
        await _client.functions.invoke(
          'refund-order',
          body: <String, dynamic>{'order_id': o['id'], 'reason': 'Event cancelled by the club'},
        );
        refunded++;
      } catch (e) {
        failures.add('${o['reference']}: ${describeError(e)}');
      }
    }
    return CancelResult(refunded: refunded, failures: failures);
  }

  // ----------------------------------------------------------------- images

  static const Map<String, String> _imageTypes = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };
  static const int maxImageBytes = 8 * 1024 * 1024; // bucket allows 10 MB; leave headroom

  /// Uploads to the public `event-images` bucket and returns the public URL.
  Future<String> uploadImage({required Uint8List bytes, required String fileName}) async {
    final String ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    final String? contentType = _imageTypes[ext];
    if (contentType == null) throw EventAdminException('Use a JPG, PNG or WebP picture.');
    if (bytes.length > maxImageBytes) throw EventAdminException('That picture is over 8 MB — try a smaller one.');

    final String path = 'events/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await _client.storage.from(_imageBucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType));
    return _client.storage.from(_imageBucket).getPublicUrl(path);
  }

  // ------------------------------------------------------------------- push

  /// [preview] = count the audience without sending anything.
  Future<PushResult> sendPush({
    required String kind,
    required String audience,
    required String title,
    required String body,
    String? eventId,
    bool preview = false,
  }) async {
    final response = await _client.functions.invoke(
      'send-push',
      body: <String, dynamic>{
        'kind': kind,
        'audience': audience,
        'title': title,
        'body': body,
        'event_id': ?eventId,
        'preview': preview,
      },
    );
    final dynamic data = response.data;
    if (data is! Map) throw EventAdminException('The notification service gave an unexpected answer.');
    return PushResult(
      recipients: (data['recipients'] as num?)?.toInt() ?? 0,
      delivered: (data['delivered'] as num?)?.toInt() ?? 0,
      failed: (data['failed'] as num?)?.toInt() ?? 0,
      preview: preview,
    );
  }

  Future<List<Map<String, dynamic>>> pushCampaigns({String? eventId, int limit = 20}) async {
    var query = _client.from('push_campaigns').select('title, body, audience, kind, status, recipients, delivered, created_at');
    if (eventId != null) query = query.eq('event_id', eventId);
    return List<Map<String, dynamic>>.from(await query.order('created_at', ascending: false).limit(limit));
  }

  // ---------------------------------------------------------------- history

  /// Admin-only (audit_log RLS). Newest first, with the person's name.
  Future<List<Map<String, dynamic>>> eventHistory(String eventId) async {
    final rows = await _client
        .from('audit_log')
        .select('action, created_at, before, after, actor_id')
        .eq('entity_id', eventId)
        .order('created_at', ascending: false)
        .limit(40);

    final Set<String> actorIds = <String>{
      for (final Map<String, dynamic> r in rows) if (r['actor_id'] != null) r['actor_id'] as String,
    };
    final Map<String, String> names = <String, String>{};
    if (actorIds.isNotEmpty) {
      final people = await _client.from('profiles').select('id, display_name, full_name, email').inFilter('id', actorIds.toList());
      for (final Map<String, dynamic> p in people) {
        names[p['id'] as String] = (p['display_name'] ?? p['full_name'] ?? p['email'] ?? 'Unknown') as String;
      }
    }
    return <Map<String, dynamic>>[
      for (final Map<String, dynamic> r in rows) <String, dynamic>{...r, 'actor_name': names[r['actor_id']] ?? 'System'},
    ];
  }
}
