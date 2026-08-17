import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/local_db/app_database_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import 'data/ticket_secrets_store.dart';
import 'data/tickets_local_data_source.dart';
import 'data/tickets_remote_data_source.dart';
import 'data/tickets_repository.dart';

final Provider<TicketsRemoteDataSource> _ticketsRemoteDataSourceProvider = Provider<TicketsRemoteDataSource>((ref) {
  return TicketsRemoteDataSource(ref.watch(supabaseClientProvider));
});

final Provider<TicketsLocalDataSource> _ticketsLocalDataSourceProvider = Provider<TicketsLocalDataSource>((ref) {
  return TicketsLocalDataSource(ref.watch(appDatabaseProvider));
});

final Provider<TicketSecretsStore> _ticketSecretsStoreProvider = Provider<TicketSecretsStore>((ref) {
  return TicketSecretsStore(const FlutterSecureStorage());
});

final Provider<TicketsRepository> ticketsRepositoryProvider = Provider<TicketsRepository>((ref) {
  return TicketsRepository(
    ref.watch(_ticketsRemoteDataSourceProvider),
    ref.watch(_ticketsLocalDataSourceProvider),
    ref.watch(_ticketSecretsStoreProvider),
  );
});
