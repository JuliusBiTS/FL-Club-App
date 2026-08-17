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

@DriftDatabase(tables: [CachedEvents, CachedArticles, CachedPodcastEpisodes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

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

  Future<List<CachedEvent>> publishedEventsSortedByStart() {
    return (select(cachedEvents)
          ..where((t) => t.status.equals('published'))
          ..orderBy([(t) => OrderingTerm.asc(t.startsAt)]))
        .get();
  }

  Future<CachedEvent?> eventBySlug(String slug) {
    return (select(cachedEvents)..where((t) => t.slug.equals(slug))).getSingleOrNull();
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
