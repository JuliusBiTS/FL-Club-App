import 'dart:convert';

import 'package:flc_core/flc_core.dart';

import '../../../core/local_db/app_database.dart';

/// Drift-backed cache. See app_database.dart for why this stores JSON
/// blobs rather than fully normalised columns. Playback progress is never
/// cached locally — it's small, per-account, and always worth a fresh
/// fetch rather than risking a stale resume position.
class PodcastLocalDataSource {
  PodcastLocalDataSource(this._db);

  final AppDatabase _db;

  Future<List<PodcastEpisodeModel>> readCachedLatest() async {
    final rows = await _db.podcastEpisodesSortedByPublished();
    return rows.map((row) => PodcastEpisodeModel.fromJson(jsonDecode(row.json) as Map<String, dynamic>)).toList();
  }

  Future<void> writeEpisodes(List<PodcastEpisodeModel> episodes) {
    return _db.upsertPodcastEpisodes([
      for (final episode in episodes) (episode.id, episode.guid, episode.publishedAt, jsonEncode(episode.toJson())),
    ]);
  }
}
