import 'package:flc_core/flc_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local_db/app_database_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import 'data/events_local_data_source.dart';
import 'data/events_remote_data_source.dart';
import 'data/events_repository_impl.dart';
import 'domain/events_repository.dart';

final Provider<EventsRemoteDataSource> _eventsRemoteDataSourceProvider = Provider<EventsRemoteDataSource>((ref) {
  return EventsRemoteDataSource(ref.watch(supabaseClientProvider));
});

final Provider<EventsLocalDataSource> _eventsLocalDataSourceProvider = Provider<EventsLocalDataSource>((ref) {
  return EventsLocalDataSource(ref.watch(appDatabaseProvider));
});

final Provider<EventsRepository> eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  return EventsRepositoryImpl(
    ref.watch(_eventsRemoteDataSourceProvider),
    ref.watch(_eventsLocalDataSourceProvider),
  );
});

/// One ticket-types fetch per event detail visit — always live, per §8.2:
/// "any price the app displays comes from the API", no cached price
/// arithmetic. autoDispose so a stale price list can never linger once the
/// user leaves the screen.
final ticketTypesProvider = FutureProvider.autoDispose.family<List<TicketTypeModel>, String>((ref, eventId) {
  return ref.watch(eventsRepositoryProvider).getTicketTypes(eventId);
});

final eventDetailProvider = FutureProvider.autoDispose.family<EventModel?, String>((ref, slug) {
  return ref.watch(eventsRepositoryProvider).getEventDetail(slug);
});
