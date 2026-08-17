import 'package:freezed_annotation/freezed_annotation.dart';

part 'playback_progress.freezed.dart';
part 'playback_progress.g.dart';

/// Mirrors `playback_progress` — owner-writable directly by the client
/// under RLS (`playback_progress_owner_all`), no Edge Function needed.
/// `user_id` isn't modelled here: it's an RLS/query key, never a field the
/// client needs to read back about itself.
@freezed
abstract class PlaybackProgressModel with _$PlaybackProgressModel {
  const factory PlaybackProgressModel({
    @JsonKey(name: 'episode_id') required String episodeId,
    @JsonKey(name: 'position_seconds') @Default(0) int positionSeconds,
    @Default(false) bool completed,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _PlaybackProgressModel;

  factory PlaybackProgressModel.fromJson(Map<String, dynamic> json) => _$PlaybackProgressModelFromJson(json);
}
