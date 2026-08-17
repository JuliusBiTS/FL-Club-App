import 'package:flc_core/flc_core.dart';

import 'ticket_secrets_store.dart';
import 'tickets_local_data_source.dart';
import 'tickets_remote_data_source.dart';

class TicketsRepository {
  TicketsRepository(this._remote, this._local, this._secrets);

  final TicketsRemoteDataSource _remote;
  final TicketsLocalDataSource _local;
  final TicketSecretsStore _secrets;

  Future<List<TicketModel>> getCachedTickets() => _local.readCached();

  Future<List<TicketModel>> refreshTickets() async {
    final result = await _remote.fetchMyTickets();
    await _local.writeTickets(result.tickets);
    await _secrets.replaceAll(result.secrets);
    return result.tickets;
  }

  /// Null means "not cached yet" (offline, never synced) — the detail
  /// screen shows a "reconnect to load this ticket" state rather than a
  /// fake/blank QR in that case.
  Future<String?> getTicketSecret(String ticketId) => _secrets.secretFor(ticketId);
}
