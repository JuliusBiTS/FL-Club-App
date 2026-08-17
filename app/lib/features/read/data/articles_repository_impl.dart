import 'package:flc_core/flc_core.dart';

import '../domain/articles_repository.dart';
import 'articles_local_data_source.dart';
import 'articles_remote_data_source.dart';

class ArticlesRepositoryImpl implements ArticlesRepository {
  ArticlesRepositoryImpl(this._remote, this._local);

  final ArticlesRemoteDataSource _remote;
  final ArticlesLocalDataSource _local;

  @override
  Future<List<ArticleModel>> getCachedArticles() => _local.readCachedLatest();

  @override
  Future<List<ArticleModel>> refreshArticles() async {
    final fresh = await _remote.fetchLatest();
    await _local.writeArticles(fresh);
    return fresh;
  }

  @override
  Future<ArticleModel?> getArticleDetail(String slug, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await _local.readCachedBySlug(slug);
      if (cached != null) return cached;
    }
    final fresh = await _remote.fetchBySlug(slug);
    if (fresh != null) {
      await _local.writeArticles([fresh]);
    }
    return fresh;
  }
}
