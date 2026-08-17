import 'package:flc_core/flc_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local_db/app_database_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import 'data/articles_local_data_source.dart';
import 'data/articles_remote_data_source.dart';
import 'data/articles_repository_impl.dart';
import 'domain/articles_repository.dart';

final Provider<ArticlesRemoteDataSource> _articlesRemoteDataSourceProvider = Provider<ArticlesRemoteDataSource>((ref) {
  return ArticlesRemoteDataSource(ref.watch(supabaseClientProvider));
});

final Provider<ArticlesLocalDataSource> _articlesLocalDataSourceProvider = Provider<ArticlesLocalDataSource>((ref) {
  return ArticlesLocalDataSource(ref.watch(appDatabaseProvider));
});

final Provider<ArticlesRepository> articlesRepositoryProvider = Provider<ArticlesRepository>((ref) {
  return ArticlesRepositoryImpl(
    ref.watch(_articlesRemoteDataSourceProvider),
    ref.watch(_articlesLocalDataSourceProvider),
  );
});

final articleDetailProvider = FutureProvider.autoDispose.family<ArticleModel?, String>((ref, slug) {
  return ref.watch(articlesRepositoryProvider).getArticleDetail(slug);
});
