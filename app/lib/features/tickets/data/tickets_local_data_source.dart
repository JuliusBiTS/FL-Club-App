import 'dart:convert';

import 'package:flc_core/flc_core.dart';

import '../../../core/local_db/app_database.dart';

/// Drift-backed cache for ticket display metadata — see CachedTickets'
/// doc comment for why ticket_secret is never part of this.
class TicketsLocalDataSource {
  TicketsLocalDataSource(this._db);

  final AppDatabase _db;

  Future<List<TicketModel>> readCached() async {
    final rows = await _db.allCachedTicketsSortedByStart();
    return rows.map((row) => TicketModel.fromCacheJson(jsonDecode(row.json) as Map<String, dynamic>)).toList();
  }

  Future<void> writeTickets(List<TicketModel> tickets) {
    return _db.replaceAllTickets([
      for (final ticket in tickets) (ticket.id, ticket.eventStartsAt, ticket.status, jsonEncode(ticket.toCacheJson())),
    ]);
  }
}
