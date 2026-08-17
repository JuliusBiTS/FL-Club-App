import 'package:flc_core/flc_core.dart';

import '../domain/podcast_repository.dart';
import 'podcast_local_data_source.dart';
import 'podcast_remote_data_source.dart';

class PodcastRepositoryImpl implements PodcastRepository {
  PodcastRepositoryImpl(this._remote, this._local, this._currentUserId);

  final PodcastRemoteDataSource _remote;
  final PodcastLocalDataSource _local;
  final String? Function() _currentUserId;

  @override
  Future<List<PodcastEpisodeModel>> getCachedEpisodes() => _local.readCachedLatest();

  @override
  Future<List<PodcastEpisodeModel>> refreshEpisodes() async {
    final fresh = await _remote.fetchLatest();
    await _local.writeEpisodes(fresh);
    return fresh;
  }

  @override
  Future<Map<String, PlaybackProgressModel>> getPlaybackProgress() async {
    final userId = _currentUserId();
    if (userId == null) return const {};
    return _remote.fetchProgress(userId);
  }

  @override
  Future<void> saveProgress(String episodeId, Duration position, bool completed) async {
    final userId = _currentUserId();
    if (userId == null) return;
    await _remote.upsertProgress(userId, episodeId, position.inSeconds, completed);
  }
}
