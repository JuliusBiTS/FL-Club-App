import 'package:freezed_annotation/freezed_annotation.dart';

part 'article.freezed.dart';
part 'article.g.dart';

/// Mirrors `articles`, synced one-way (WordPress -> Supabase, never back)
/// by the wordpress-sync Edge Function (briefing §9.9/§12.3). content_html
/// is already sanitised server-side against a strict tag allow-list, but
/// the widget rendering it should still use the same allow-list rather
/// than trusting that blindly — belt and braces.
@freezed
abstract class ArticleModel with _$ArticleModel {
  const factory ArticleModel({
    required String id,
    @JsonKey(name: 'wp_post_id') int? wpPostId,
    required String slug,
    required String title,
    String? excerpt,
    @JsonKey(name: 'content_html') String? contentHtml,
    @JsonKey(name: 'hero_image_url') String? heroImageUrl,
    @JsonKey(name: 'author_name') String? authorName,
    @Default(<String>[]) List<String> categories,
    @JsonKey(name: 'canonical_url') required String canonicalUrl,
    @JsonKey(name: 'published_at') required DateTime publishedAt,
  }) = _ArticleModel;

  factory ArticleModel.fromJson(Map<String, dynamic> json) => _$ArticleModelFromJson(json);
}
