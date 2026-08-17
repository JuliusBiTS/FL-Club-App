import 'dart:convert';

import 'package:flc_core/flc_core.dart';

import '../../../core/local_db/app_database.dart';

/// Drift-backed cache. See app_database.dart for why this stores JSON
/// blobs rather than fully normalised columns.
class EventsLocalDataSource {
  EventsLocalDataSource(this._db);

  final AppDatabase _db;

  Future<List<EventModel>> readCachedUpcoming() async {
    final rows = await _db.publishedEventsSortedByStart();
    return rows.map((row) => EventModel.fromJson(jsonDecode(row.json) as Map<String, dynamic>)).toList();
  }

  Future<EventModel?> readCachedBySlug(String slug) async {
    final row = await _db.eventBySlug(slug);
    if (row == null) return null;
    return EventModel.fromJson(jsonDecode(row.json) as Map<String, dynamic>);
  }

  Future<void> writeEvents(List<EventModel> events) {
    return _db.upsertEvents([
      for (final event in events) (event.id, event.slug, event.startsAt, event.status, jsonEncode(event.toJson())),
    ]);
  }
}
