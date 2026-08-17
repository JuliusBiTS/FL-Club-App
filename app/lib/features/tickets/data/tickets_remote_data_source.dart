import 'package:flc_core/flc_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TicketsFetchResult {
  const TicketsFetchResult(this.tickets, this.secrets);

  final List<TicketModel> tickets;
  final Map<String, String> secrets; // ticketId -> base64url ticket_secret
}

class TicketsRemoteDataSource {
  TicketsRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<TicketsFetchResult> fetchMyTickets() async {
    final response = await _client.functions.invoke('get-my-tickets');
    final data = response.data as Map<String, dynamic>;
    final rows = (data['tickets'] as List<dynamic>).cast<Map<String, dynamic>>();

    final tickets = <TicketModel>[];
    final secrets = <String, String>{};
    for (final row in rows) {
      tickets.add(TicketModel.fromApiJson(row));
      secrets[row['ticket_id'] as String] = row['ticket_secret'] as String;
    }
    return TicketsFetchResult(tickets, secrets);
  }
}
