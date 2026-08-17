import 'package:flc_core/flc_core.dart';

/// The only thing controllers/widgets are allowed to depend on for article
/// data — same offline-first contract as EventsRepository (briefing §7.3).
abstract class ArticlesRepository {
  Future<List<ArticleModel>> getCachedArticles();

  Future<List<ArticleModel>> refreshArticles();

  Future<ArticleModel?> getArticleDetail(String slug, {bool forceRefresh = false});
}
