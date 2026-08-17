import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Offline-first local cache — briefing §7.3: "Every read goes to Drift
/// first, then revalidates from the network in the background."
///
/// Deliberate simplification for this scaffold: rather than mirroring
/// every remote table's columns 1:1 in Drift (which then has to be kept in
/// lock-step with every Postgres migration by hand), each cached table
/// stores the row's `id`, enough fields to sort/query without deserialising
/// everything, and the full row as a JSON blob that the same
/// `EventModel.fromJson` /o data-source freezed factories parse. This
/// trades a little query power (no SQL filtering on arbitrary JSON fields)
/// for a cache that can never drift out of sync with the API contract. If
/// a screen later needs real local filtering (e.g. full-text search while
/// offline), promote that table to real columns then — don't do it
/// speculatively for every table now.
class CachedEvents extends Table {
  TextColumn get id => text()();
  TextColumn get slug => text()();
  DateTimeColumn get startsAt => dateTime()();
  TextColumn get status => text()();
  TextColumn get json => text()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class CachedArticles extends Table {
  TextColumn get id => text()();
  TextColumn get slug => text()();
  DateTimeColumn get publishedAt => dateTime()();
  TextColumn get json => text()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class CachedPodcastEpisodes extends Table {
  TextColumn get id => text()();
  TextColumn get guid => text()();
  DateTimeColumn get publishedAt => dateTime()();
  TextColumn get json => text()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ticket display metadata only — briefing §9.4 "offline rendering from
/// local secure storage" applies to the ticket_secret specifically, which
/// deliberately does NOT live here. It's sensitive (it's what lets a device
/// mint a valid rotating QR) while this table's contents are not — a stolen
/// phone showing "Standard ticket, Thu 10 Sep" isn't a security problem the
/// way a stolen ticket_secret would be. See tickets_repository.dart.
class CachedTickets extends Table {
  TextColumn get id => text()();
  DateTimeColumn get eventStartsAt => dateTime()();
  TextColumn get status => text()();
  TextColumn get json => text()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per event a staff device has downloaded an offline scan pack
/// for (briefing §13.5) — `expiresAt` mirrors get-scan-pack's own
/// `expires_at` (event end + 6h) so the app can warn staff their pack is
/// stale rather than silently refusing scans with no explanation.
class CachedScanPacks extends Table {
  TextColumn get eventId => text()();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get downloadedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {eventId};
}

/// A scan pack's ticket list — `status` starts as whatever get-scan-pack
/// returned and is updated locally the instant a ticket is redeemed
/// offline, so a second offline scan of the same code is caught
/// immediately without waiting for a sync round-trip. The eventual
/// verify-scan sync is still the source of truth (it resolves conflicts
/// between two staff devices that redeemed the same ticket offline,
/// briefing §13.5 point 6) — this is just what keeps one device from
/// admitting the same person twice before it gets the chance to sync.
class CachedScanPackTickets extends Table {
  TextColumn get id => text()(); // ticket_id
  TextColumn get eventId => text()();
  TextColumn get status => text()();
  TextColumn get json => text()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Offline-redeemed scans awaiting their batch sync to verify-scan.
/// `payload` is the raw scanned QR string (not just the ticket id) —
/// verify-scan re-parses and re-verifies every scan server-side rather
/// than trusting the client's local verification, so the original
/// payload has to survive the round trip.
class PendingScanSyncs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get ticketId => text()();
  TextColumn get eventId => text()();
  TextColumn get payload => text()();
  DateTimeColumn get scannedAt => dateTime()();
  BoolColumn get wasOffline => boolean().withDefault(const Constant(true))();
}

@DriftDatabase(tables: [
  CachedEvents,
  CachedArticles,
  CachedPodcastEpisodes,
  CachedTickets,
  CachedScanPacks,
  CachedScanPackTickets,
  PendingScanSyncs,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(cachedTickets);
          }
          if (from < 3) {
            await m.createTable(cachedScanPacks);
            await m.createTable(cachedScanPackTickets);
            await m.createTable(pendingScanSyncs);
          }
        },
      );

  Future<void> upsertEvents(List<(String id, String slug, DateTime startsAt, String status, String json)> rows) {
    return batch((batchBuilder) {
      for (final row in rows) {
        batchBuilder.insert(
          cachedEvents,
          CachedEventsCompanion.insert(
            id: row.$1,
            slug: row.$2,
            startsAt: row.$3,
            status: row.$4,
            json: row.$5,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<void> replaceAllTickets(List<(String id, DateTime eventStartsAt, String status, String json)> rows) {
    return transaction(() async {
      await delete(cachedTickets).go();
      await batch((batchBuilder) {
        for (final row in rows) {
          batchBuilder.insert(
            cachedTickets,
            CachedTicketsCompanion.insert(
              id: row.$1,
              eventStartsAt: row.$2,
              status: row.$3,
              json: row.$4,
            ),
          );
        }
      });
    });
  }

  Future<List<CachedTicket>> allCachedTicketsSortedByStart() {
    return (select(cachedTickets)..orderBy([(t) => OrderingTerm.asc(t.eventStartsAt)])).get();
  }

  Future<List<CachedEvent>> publishedEventsSortedByStart() {
    return (select(cachedEvents)
          ..where((t) => t.status.equals('published'))
          ..orderBy([(t) => OrderingTerm.asc(t.startsAt)]))
        .get();
  }

  Future<CachedEvent?> eventBySlug(String slug) {
    return (select(cachedEvents)..where((t) => t.slug.equals(slug))).getSingleOrNull();
  }

  Future<void> upsertArticles(List<(String id, String slug, DateTime publishedAt, String json)> rows) {
    return batch((batchBuilder) {
      for (final row in rows) {
        batchBuilder.insert(
          cachedArticles,
          CachedArticlesCompanion.insert(id: row.$1, slug: row.$2, publishedAt: row.$3, json: row.$4),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<List<CachedArticle>> articlesSortedByPublished() {
    return (select(cachedArticles)..orderBy([(t) => OrderingTerm.desc(t.publishedAt)])).get();
  }

  Future<CachedArticle?> articleBySlug(String slug) {
    return (select(cachedArticles)..where((t) => t.slug.equals(slug))).getSingleOrNull();
  }

  Future<void> upsertPodcastEpisodes(List<(String id, String guid, DateTime publishedAt, String json)> rows) {
    return batch((batchBuilder) {
      for (final row in rows) {
        batchBuilder.insert(
          cachedPodcastEpisodes,
          CachedPodcastEpisodesCompanion.insert(id: row.$1, guid: row.$2, publishedAt: row.$3, json: row.$4),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<List<CachedPodcastEpisode>> podcastEpisodesSortedByPublished() {
    return (select(cachedPodcastEpisodes)..orderBy([(t) => OrderingTerm.desc(t.publishedAt)])).get();
  }

  Future<void> saveScanPack(
    String eventId,
    DateTime expiresAt,
    List<(String id, String status, String json)> tickets,
  ) {
    return transaction(() async {
      await into(cachedScanPacks).insert(
        CachedScanPacksCompanion.insert(eventId: eventId, expiresAt: expiresAt),
        mode: InsertMode.insertOrReplace,
      );
      await (delete(cachedScanPackTickets)..where((t) => t.eventId.equals(eventId))).go();
      await batch((batchBuilder) {
        for (final row in tickets) {
          batchBuilder.insert(
            cachedScanPackTickets,
            CachedScanPackTicketsCompanion.insert(id: row.$1, eventId: eventId, status: row.$2, json: row.$3),
          );
        }
      });
    });
  }

  Future<CachedScanPack?> scanPackFor(String eventId) {
    return (select(cachedScanPacks)..where((t) => t.eventId.equals(eventId))).getSingleOrNull();
  }

  Future<List<CachedScanPackTicket>> scanPackTicketsFor(String eventId) {
    return (select(cachedScanPackTickets)..where((t) => t.eventId.equals(eventId))).get();
  }

  Future<CachedScanPackTicket?> scanPackTicketById(String ticketId) {
    return (select(cachedScanPackTickets)..where((t) => t.id.equals(ticketId))).getSingleOrNull();
  }

  Future<void> markScanPackTicketStatus(String ticketId, String status) {
    return (update(cachedScanPackTickets)..where((t) => t.id.equals(ticketId)))
        .write(CachedScanPackTicketsCompanion(status: Value(status)));
  }

  Future<int> enqueuePendingScan({
    required String ticketId,
    required String eventId,
    required String payload,
    required DateTime scannedAt,
    bool wasOffline = true,
  }) {
    return into(pendingScanSyncs).insert(
      PendingScanSyncsCompanion.insert(
        ticketId: ticketId,
        eventId: eventId,
        payload: payload,
        scannedAt: scannedAt,
        wasOffline: Value(wasOffline),
      ),
    );
  }

  Future<List<PendingScanSync>> pendingScansFor(String eventId) {
    return (select(pendingScanSyncs)..where((t) => t.eventId.equals(eventId))).get();
  }

  Future<void> deletePendingScans(List<int> ids) {
    return (delete(pendingScanSyncs)..where((t) => t.id.isIn(ids))).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'flc_cache.sqlite'));
    return NativeDatabase.createInBackground(
      file,
      setup: (rawDb) {
        // WAL + a busy timeout make the initial open resilient to
        // transient lock contention — observed in practice on Android
        // when the engine briefly starts a second isolate during cold
        // start, both racing to open the same file. Without this the
        // second opener gets SqliteException(5) "database is locked"
        // instead of just waiting its turn.
        rawDb.execute('PRAGMA journal_mode=WAL;');
        rawDb.execute('PRAGMA busy_timeout = 5000;');
      },
    );
  });
}
