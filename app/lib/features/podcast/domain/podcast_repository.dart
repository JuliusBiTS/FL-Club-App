import 'package:flc_core/flc_core.dart';

/// The only thing controllers/widgets are allowed to depend on for podcast
/// data — same offline-first contract as EventsRepository (briefing §7.3).
abstract class PodcastRepository {
  Future<List<PodcastEpisodeModel>> getCachedEpisodes();

  Future<List<PodcastEpisodeModel>> refreshEpisodes();

  /// Keyed by episode_id. Empty for a signed-out listener — resuming
  /// playback across sessions/devices is an account perk, not a
  /// requirement to listen at all (briefing §9.8: "no account required").
  Future<Map<String, PlaybackProgressModel>> getPlaybackProgress();

  /// No-ops for a signed-out listener rather than throwing — playback
  /// itself must never be blocked on having an account.
  Future<void> saveProgress(String episodeId, Duration position, bool completed);
}
