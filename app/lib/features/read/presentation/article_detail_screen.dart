import 'package:cached_network_image/cached_network_image.dart';
import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ui/membership_handle_visibility.dart';
import '../read_providers.dart';

/// Claims showMembershipHandleProvider for its lifetime — the "Read on the
/// website" button at the bottom sits in the same spot as AppShell's
/// persistent "Become a member" handle (briefing §9.6), same conflict/fix
/// as event_detail_screen's "Get tickets" bar. See that provider's doc
/// comment.
class ArticleDetailScreen extends ConsumerStatefulWidget {
  const ArticleDetailScreen({required this.slug, super.key});

  final String slug;

  @override
  ConsumerState<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends ConsumerState<ArticleDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(showMembershipHandleProvider.notifier).state = false;
    });
  }

  @override
  void dispose() {
    ref.read(showMembershipHandleProvider.notifier).state = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final articleAsync = ref.watch(articleDetailProvider(widget.slug));

    return Scaffold(
      body: articleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(child: Text('Could not load this article.')),
        data: (article) {
          if (article == null) return const Center(child: Text('Article not found.'));
          return _ArticleDetailBody(article: article);
        },
      ),
    );
  }
}

class _ArticleDetailBody extends StatelessWidget {
  const _ArticleDetailBody({required this.article});

  final ArticleModel article;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE d MMM yyyy');

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          expandedHeight: article.heroImageUrl != null ? 220 : kToolbarHeight,
          flexibleSpace: FlexibleSpaceBar(
            background: article.heroImageUrl == null
                ? null
                : CachedNetworkImage(imageUrl: article.heroImageUrl!, fit: BoxFit.cover),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(FlcSpace.md),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              if (article.categories.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: FlcSpace.xs),
                  child: Text(article.categories.first.toUpperCase(), style: FlcTextStyles.overline.copyWith(color: FlcColors.brand)),
                ),
              Text(article.title, style: FlcTextStyles.h2),
              const SizedBox(height: FlcSpace.xs),
              Text(
                <String>[
                  dateFormat.format(article.publishedAt.toLocal()),
                  if (article.authorName != null) article.authorName!,
                ].join(' · '),
                style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate),
              ),
              const SizedBox(height: FlcSpace.md),
              // content_html is already sanitised server-side against a
              // strict tag allow-list (see wordpress-sync), but this still
              // renders through HtmlWidget's own limited tag support rather
              // than trusting that blindly — belt and braces (model doc
              // comment).
              if (article.contentHtml != null) HtmlWidget(article.contentHtml!),
              const SizedBox(height: FlcSpace.lg),
              OutlinedButton(
                onPressed: () => launchUrl(Uri.parse(article.canonicalUrl), mode: LaunchMode.externalApplication),
                child: const Text('Read on the website'),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
