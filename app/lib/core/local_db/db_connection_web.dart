import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';

/// Browser: SQLite compiled to WebAssembly, held in memory. This is only the
/// offline cache, so losing it on refresh costs nothing — everything is
/// re-fetched from the server. (Needs sqlite3.wasm next to index.html, see
/// web/.)
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final WasmSqlite3 sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
    sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
    return WasmDatabase.inMemory(sqlite);
  });
}
