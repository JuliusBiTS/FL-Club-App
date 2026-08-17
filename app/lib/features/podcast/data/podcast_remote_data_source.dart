import 'package:flc_core/flc_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Talks to Supabase directly — `podcast_episodes` is public-read (RLS
/// `podcast_episodes_public_read`), no account required. `playback_progress`
/// is owner-writable directly under RLS (`playback_progress_owner_all`), so
/// this writes it straight from the client rather than through an Edge
/// Function — briefing note in the RLS migration calls this out explicitly
/// as one of the few tables that's safe for direct client writes.
class PodcastRemoteDataSource {
  PodcastRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<List<PodcastEpisodeModel>> fetchLatest({int limit = 50}) async {
    final rows = await _client.from('podcast_episodes').select().order('published_at', ascending: false).limit(limit);
    return rows.map(PodcastEpisodeModel.fromJson).toList();
  }

  Future<Map<String, PlaybackProgressModel>> fetchProgress(String userId) async {
    final rows = await _client.from('playback_progress').select().eq('user_id', userId);
    final progress = rows.map(PlaybackProgressModel.fromJson);
    return {for (final p in progress) p.episodeId: p};
  }

  Future<void> upsertProgress(String userId, String episodeId, int positionSeconds, bool completed) {
    return _client.from('playback_progress').upsert(<String, dynamic>{
      'user_id': userId,
      'episode_id': episodeId,
      'position_seconds': positionSeconds,
      'completed': completed,
    });
  }
}
