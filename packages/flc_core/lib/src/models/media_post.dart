import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_post.freezed.dart';
part 'media_post.g.dart';

/// Mirrors `media_posts` — the club's YouTube uploads/livestreams, briefing
/// feedback (2026-08-24). `source` is always 'youtube' for now; Instagram
/// is deliberately out until Meta's app review grants API access (see
/// docs/OPEN_QUESTIONS.md), so this shape only ever needs one source's
/// fields rather than a lowest-common-denominator union.
@freezed
abstract class MediaPostModel with _$MediaPostModel {
  const factory MediaPostModel({
    required String id,
    required String source,
    @JsonKey(name: 'external_id') required String externalId,
    required String title,
    String? description,
    @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,
    @JsonKey(name: 'published_at') required DateTime publishedAt,
    @JsonKey(name: 'is_live') @Default(false) bool isLive,
  }) = _MediaPostModel;

  factory MediaPostModel.fromJson(Map<String, dynamic> json) => _$MediaPostModelFromJson(json);
}
