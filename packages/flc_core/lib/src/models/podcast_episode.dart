import 'package:freezed_annotation/freezed_annotation.dart';

part 'podcast_episode.freezed.dart';
part 'podcast_episode.g.dart';

/// Mirrors `podcast_episodes`, upserted hourly by the podcast-sync Edge
/// Function from the club's public RSS feed (briefing §9.8). Requires no
/// account to read or play — it's a shop window.
@freezed
abstract class PodcastEpisodeModel with _$PodcastEpisodeModel {
  const factory PodcastEpisodeModel({
    required String id,
    required String guid,
    required String title,
    @JsonKey(name: 'description_html') String? descriptionHtml,
    @JsonKey(name: 'audio_url') required String audioUrl,
    @JsonKey(name: 'duration_seconds') int? durationSeconds,
    @JsonKey(name: 'image_url') String? imageUrl,
    @JsonKey(name: 'episode_number') int? episodeNumber,
    int? season,
    @JsonKey(name: 'published_at') required DateTime publishedAt,
    @Default(false) bool explicit,
  }) = _PodcastEpisodeModel;

  factory PodcastEpisodeModel.fromJson(Map<String, dynamic> json) => _$PodcastEpisodeModelFromJson(json);
}
