import 'dart:convert';

import 'package:flc_core/flc_core.dart';

import '../../../core/local_db/app_database.dart';

/// Drift-backed cache. See app_database.dart for why this stores JSON
/// blobs rather than fully normalised columns.
class ArticlesLocalDataSource {
  ArticlesLocalDataSource(this._db);

  final AppDatabase _db;

  Future<List<ArticleModel>> readCachedLatest() async {
    final rows = await _db.articlesSortedByPublished();
    return rows.map((row) => ArticleModel.fromJson(jsonDecode(row.json) as Map<String, dynamic>)).toList();
  }

  Future<ArticleModel?> readCachedBySlug(String slug) async {
    final row = await _db.articleBySlug(slug);
    if (row == null) return null;
    return ArticleModel.fromJson(jsonDecode(row.json) as Map<String, dynamic>);
  }

  Future<void> writeArticles(List<ArticleModel> articles) {
    return _db.upsertArticles([
      for (final article in articles) (article.id, article.slug, article.publishedAt, jsonEncode(article.toJson())),
    ]);
  }
}
