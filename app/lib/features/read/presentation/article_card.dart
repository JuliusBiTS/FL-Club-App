import 'package:cached_network_image/cached_network_image.dart';
import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'article_hero_fallback.dart';

class ArticleCard extends StatelessWidget {
  const ArticleCard({required this.article, required this.onTap, super.key});

  final ArticleModel article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE d MMM yyyy');
    final String? heroUrl = article.displayHeroImageUrl;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.xs),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 16 / 9,
              child: heroUrl == null
                  ? const ArticleHeroFallback()
                  : CachedNetworkImage(
                      imageUrl: heroUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => const ArticleHeroFallback(),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(FlcSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (article.categories.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: FlcSpace.xxs),
                      child: Text(
                        article.categories.first.toUpperCase(),
                        style: FlcTextStyles.overline.copyWith(color: FlcColors.accent(context)),
                      ),
                    ),
                  Text(article.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: FlcTextStyles.h3),
                  if (article.excerpt != null) ...<Widget>[
                    const SizedBox(height: FlcSpace.xxs),
                    Text(
                      article.excerpt!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)),
                    ),
                  ],
                  const SizedBox(height: FlcSpace.xxs),
                  Text(
                    <String>[
                      dateFormat.format(article.publishedAt.toLocal()),
                      if (article.authorName != null) article.authorName!,
                    ].join(' · '),
                    style: FlcTextStyles.caption.copyWith(color: FlcColors.secondary(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
