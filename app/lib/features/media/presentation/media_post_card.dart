import 'package:cached_network_image/cached_network_image.dart';
import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Same card shape as EventCard/EpisodeCard (thumbnail, title, meta line)
/// — a LIVE badge replaces the date for anything currently streaming.
class MediaPostCard extends StatelessWidget {
  const MediaPostCard({required this.post, required this.onTap, super.key});

  final MediaPostModel post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE d MMM');

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.xs),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: post.thumbnailUrl == null
                      ? ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest)
                      : CachedNetworkImage(imageUrl: post.thumbnailUrl!, fit: BoxFit.cover),
                ),
                const Positioned.fill(
                  child: Center(
                    child: Icon(Icons.play_circle_fill, size: 56, color: Colors.white70),
                  ),
                ),
                if (post.isLive)
                  Positioned(
                    top: FlcSpace.sm,
                    left: FlcSpace.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: FlcSpace.xs, vertical: 2),
                      decoration: BoxDecoration(color: FlcColors.error, borderRadius: BorderRadius.circular(FlcRadius.input)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.circle, size: 8, color: Colors.white),
                          SizedBox(width: 4),
                          Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(FlcSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(post.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: FlcTextStyles.h3),
                  const SizedBox(height: FlcSpace.xxs),
                  Text(
                    post.isLive ? 'Streaming now' : dateFormat.format(post.publishedAt.toLocal()),
                    style: FlcTextStyles.bodySmall.copyWith(color: post.isLive ? FlcColors.error : FlcColors.slate),
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
