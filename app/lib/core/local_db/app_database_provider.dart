import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// One AppDatabase (one SQLite connection) for the app's lifetime.
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
