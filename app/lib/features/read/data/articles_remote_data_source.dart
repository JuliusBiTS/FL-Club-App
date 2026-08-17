import 'package:flc_core/flc_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Talks to Supabase directly — `articles` is public-read (RLS
/// `articles_public_read`), no account required (briefing §9.9).
class ArticlesRemoteDataSource {
  ArticlesRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<List<ArticleModel>> fetchLatest({int limit = 50}) async {
    final rows = await _client.from('articles').select().order('published_at', ascending: false).limit(limit);
    return rows.map(ArticleModel.fromJson).toList();
  }

  Future<ArticleModel?> fetchBySlug(String slug) async {
    final row = await _client.from('articles').select().eq('slug', slug).maybeSingle();
    if (row == null) return null;
    return ArticleModel.fromJson(row);
  }
}
