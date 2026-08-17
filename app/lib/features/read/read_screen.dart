import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'presentation/article_card.dart';
import 'presentation/read_feed_controller.dart';

/// News/blog feed synced from WordPress — briefing §9.9.
class ReadScreen extends ConsumerWidget {
  const ReadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articlesAsync = ref.watch(readFeedControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Read')),
      body: articlesAsync.when(
        loading: () => const _ShimmerList(),
        error: (error, stackTrace) => _ErrorState(onRetry: () => ref.read(readFeedControllerProvider.notifier).refresh()),
        data: (articles) {
          if (articles.isEmpty) return const _EmptyState();
          return RefreshIndicator(
            onRefresh: () => ref.read(readFeedControllerProvider.notifier).refresh(),
            child: ListView.builder(
              itemCount: articles.length,
              itemBuilder: (context, index) {
                final article = articles[index];
                return ArticleCard(article: article, onTap: () => context.push('/read/${article.slug}'));
              },
            ),
          );
        },
      ),
    );
  }
}

class _ShimmerList extends StatelessWidget {
  const _ShimmerList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 6,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.xs),
        height: 220,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(FlcRadius.card),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(FlcSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.article_outlined, size: 40, color: FlcColors.slate),
            SizedBox(height: FlcSpace.sm),
            Text('No articles yet — check back soon.', textAlign: TextAlign.center, style: FlcTextStyles.body),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text("Couldn't load articles."),
          const SizedBox(height: FlcSpace.sm),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
