import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Phone/desktop: a real SQLite file on disk.
QueryExecutor openConnection() {
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
