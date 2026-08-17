import 'package:cached_network_image/cached_network_image.dart';
import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EpisodeCard extends StatelessWidget {
  const EpisodeCard({required this.episode, required this.progress, required this.onTap, super.key});

  final PodcastEpisodeModel episode;
  final PlaybackProgressModel? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE d MMM yyyy');
    final theme = Theme.of(context);
    final fraction = _progressFraction();

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.xs),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(FlcSpace.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(FlcRadius.input),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: episode.imageUrl == null
                      ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: const Icon(Icons.podcasts))
                      : CachedNetworkImage(imageUrl: episode.imageUrl!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: FlcSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(episode.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: FlcTextStyles.h3),
                    const SizedBox(height: FlcSpace.xxs),
                    Text(
                      <String>[
                        dateFormat.format(episode.publishedAt.toLocal()),
                        if (episode.durationSeconds != null) _formatDuration(episode.durationSeconds!),
                      ].join(' · '),
                      style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate),
                    ),
                    if (fraction != null) ...<Widget>[
                      const SizedBox(height: FlcSpace.xxs),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 3,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                progress?.completed ?? false ? Icons.replay_circle_filled_outlined : Icons.play_circle_outline,
                size: 32,
                color: FlcColors.brand,
              ),
            ],
          ),
        ),
      ),
    );
  }

  double? _progressFraction() {
    final p = progress;
    if (p == null || p.completed || p.positionSeconds <= 0) return null;
    final total = episode.durationSeconds;
    if (total == null || total <= 0) return null;
    return (p.positionSeconds / total).clamp(0.0, 1.0);
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
