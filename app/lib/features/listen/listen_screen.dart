import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../media/media_providers.dart';
import '../media/presentation/media_post_card.dart';
import '../podcast/audio/podcast_audio_handler.dart';
import '../podcast/podcast_providers.dart';
import '../podcast/presentation/episode_card.dart';
import '../podcast/presentation/podcast_feed_controller.dart';
import '../podcast/presentation/podcast_player_sheet.dart';

/// Which content the type chips show. Two separate tabs (Podcast, Media)
/// were overkill for two feeds that are both "things the club published" —
/// one feed, filterable, does the same job with one less thing to navigate.
enum _TypeFilter { all, podcast, video }

final StateProvider<_TypeFilter> _typeFilterProvider = StateProvider<_TypeFilter>((ref) => _TypeFilter.all);

/// `null` = every season. Reset whenever the type filter leaves Podcast, so
/// switching to Video (or back to All) never leaves a stale season applied.
final StateProvider<int?> _seasonFilterProvider = StateProvider<int?>((ref) => null);

/// One merged, chronological feed of the podcast and the club's own videos
/// — briefing feedback: two tabs for two small feeds was one tab too many.
/// Filterable by content type, and (for the podcast) by season.
class ListenScreen extends ConsumerStatefulWidget {
  const ListenScreen({super.key});

  @override
  ConsumerState<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends ConsumerState<ListenScreen> {
  Timer? _progressTimer;
  StreamSubscription<PlaybackState>? _playbackSub;
  String? _trackedEpisodeId;

  @override
  void dispose() {
    _progressTimer?.cancel();
    _playbackSub?.cancel();
    super.dispose();
  }

  Future<void> _playEpisode(PodcastEpisodeModel episode) async {
    final handler = ref.read(podcastAudioHandlerProvider);
    final progress = ref.read(playbackProgressProvider).valueOrNull?[episode.id];
    final startAt = (progress != null && !progress.completed) ? Duration(seconds: progress.positionSeconds) : Duration.zero;

    await handler.loadAndPlay(
      episode,
      startAt: startAt,
      onCompleted: () {
        ref.read(podcastRepositoryProvider).saveProgress(episode.id, handler.duration ?? Duration.zero, true);
        ref.invalidate(playbackProgressProvider);
      },
    );
    _trackProgress(handler, episode.id);
    if (mounted) PodcastPlayerSheet.show(context, handler);
  }

  void _trackProgress(PodcastAudioHandler handler, String episodeId) {
    _progressTimer?.cancel();
    _playbackSub?.cancel();
    _trackedEpisodeId = episodeId;

    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      ref.read(podcastRepositoryProvider).saveProgress(episodeId, handler.position, false);
    });

    var wasPlaying = false;
    _playbackSub = handler.playbackState.listen((state) {
      if (wasPlaying && !state.playing && _trackedEpisodeId == episodeId) {
        ref.read(podcastRepositoryProvider).saveProgress(episodeId, handler.position, false);
      }
      wasPlaying = state.playing;
    });
  }

  @override
  Widget build(BuildContext context) {
    final episodesAsync = ref.watch(podcastFeedControllerProvider);
    final postsAsync = ref.watch(mediaFeedControllerProvider);
    final typeFilter = ref.watch(_typeFilterProvider);
    final season = ref.watch(_seasonFilterProvider);
    final handler = ref.watch(podcastAudioHandlerProvider);

    final bool loading = episodesAsync.isLoading && postsAsync.isLoading;
    final Object? error = episodesAsync.hasError && postsAsync.hasError ? episodesAsync.error : null;

    final List<PodcastEpisodeModel> episodes = episodesAsync.valueOrNull ?? const <PodcastEpisodeModel>[];
    final List<MediaPostModel> posts = postsAsync.valueOrNull ?? const <MediaPostModel>[];
    final List<int> seasons = <int>{for (final PodcastEpisodeModel e in episodes) if (e.season != null) e.season!}.toList()..sort((a, b) => b.compareTo(a));

    final List<_FeedEntry> entries = <_FeedEntry>[
      if (typeFilter != _TypeFilter.video) for (final PodcastEpisodeModel e in episodes) if (season == null || e.season == season) _FeedEntry.episode(e),
      if (typeFilter != _TypeFilter.podcast) for (final MediaPostModel p in posts) _FeedEntry.post(p),
    ]..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    return Scaffold(
      appBar: AppBar(title: const Text('Listen & Watch')),
      body: Column(
        children: <Widget>[
          _FilterRow(
            typeFilter: typeFilter,
            season: season,
            seasons: seasons,
            onTypeChanged: (t) {
              ref.read(_typeFilterProvider.notifier).state = t;
              if (t != _TypeFilter.podcast && t != _TypeFilter.all) ref.read(_seasonFilterProvider.notifier).state = null;
            },
            onSeasonChanged: (s) => ref.read(_seasonFilterProvider.notifier).state = s,
          ),
          Expanded(
            child: loading
                ? const _ShimmerList()
                : (error != null && entries.isEmpty)
                    ? _ErrorState(
                        onRetry: () {
                          ref.read(podcastFeedControllerProvider.notifier).refresh();
                          ref.read(mediaFeedControllerProvider.notifier).refresh();
                        },
                      )
                    : entries.isEmpty
                        ? const _EmptyState()
                        : RefreshIndicator(
                            onRefresh: () async {
                              await Future.wait<void>(<Future<void>>[
                                ref.read(podcastFeedControllerProvider.notifier).refresh(),
                                ref.read(mediaFeedControllerProvider.notifier).refresh(),
                              ]);
                            },
                            child: ListView.builder(
                              itemCount: entries.length,
                              itemBuilder: (context, index) {
                                final entry = entries[index];
                                if (entry.episode != null) {
                                  final progress = ref.watch(playbackProgressProvider).valueOrNull?[entry.episode!.id];
                                  return EpisodeCard(episode: entry.episode!, progress: progress, onTap: () => _playEpisode(entry.episode!));
                                }
                                final post = entry.post!;
                                return MediaPostCard(
                                  post: post,
                                  onTap: () => launchUrl(Uri.parse('https://www.youtube.com/watch?v=${post.externalId}'), mode: LaunchMode.externalApplication),
                                );
                              },
                            ),
                          ),
          ),
          // The Listen tab's own mini-player claims this space via AppShell
          // (currentMediaItemProvider + the active-tab check) — see
          // app_shell.dart. No local claim/release call needed here at all,
          // which is exactly what fixed the old "membership card gone for
          // the rest of the session" bug: there's nothing to forget to reset.
          StreamBuilder<MediaItem?>(
            stream: handler.mediaItem,
            builder: (context, snapshot) {
              final mediaItem = snapshot.data;
              if (mediaItem == null) return const SizedBox.shrink();
              return _MiniPlayerBar(handler: handler, mediaItem: mediaItem, onTap: () => PodcastPlayerSheet.show(context, handler));
            },
          ),
        ],
      ),
    );
  }
}

class _FeedEntry {
  _FeedEntry.episode(this.episode) : post = null, publishedAt = episode!.publishedAt;
  _FeedEntry.post(this.post) : episode = null, publishedAt = post!.publishedAt;

  final PodcastEpisodeModel? episode;
  final MediaPostModel? post;
  final DateTime publishedAt;
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.typeFilter,
    required this.season,
    required this.seasons,
    required this.onTypeChanged,
    required this.onSeasonChanged,
  });

  final _TypeFilter typeFilter;
  final int? season;
  final List<int> seasons;
  final ValueChanged<_TypeFilter> onTypeChanged;
  final ValueChanged<int?> onSeasonChanged;

  @override
  Widget build(BuildContext context) {
    final bool showSeasons = seasons.length > 1 && typeFilter != _TypeFilter.video;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.xs),
            children: <Widget>[
              _chip(context, 'All', typeFilter == _TypeFilter.all, () => onTypeChanged(_TypeFilter.all)),
              const SizedBox(width: FlcSpace.xs),
              _chip(context, 'Podcast', typeFilter == _TypeFilter.podcast, () => onTypeChanged(_TypeFilter.podcast)),
              const SizedBox(width: FlcSpace.xs),
              _chip(context, 'Videos', typeFilter == _TypeFilter.video, () => onTypeChanged(_TypeFilter.video)),
            ],
          ),
        ),
        if (showSeasons)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md),
              children: <Widget>[
                _chip(context, 'All seasons', season == null, () => onSeasonChanged(null), compact: true),
                for (final int s in seasons) ...<Widget>[
                  const SizedBox(width: FlcSpace.xs),
                  _chip(context, 'Season $s', season == s, () => onSeasonChanged(s), compact: true),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, bool selected, VoidCallback onTap, {bool compact = false}) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      visualDensity: compact ? VisualDensity.compact : null,
      onSelected: (_) => onTap(),
    );
  }
}

class _MiniPlayerBar extends StatelessWidget {
  const _MiniPlayerBar({required this.handler, required this.mediaItem, required this.onTap});

  final PodcastAudioHandler handler;
  final MediaItem mediaItem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FlcColors.ink,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.sm),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  mediaItem.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FlcTextStyles.body.copyWith(color: Colors.white),
                ),
              ),
              StreamBuilder<PlaybackState>(
                stream: handler.playbackState,
                builder: (context, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  return IconButton(
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
                    onPressed: playing ? handler.pause : handler.play,
                  );
                },
              ),
            ],
          ),
        ),
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
        height: 96,
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
            Icon(Icons.graphic_eq_outlined, size: 40, color: FlcColors.slate),
            SizedBox(height: FlcSpace.sm),
            Text('Nothing here yet — check back soon.', textAlign: TextAlign.center, style: FlcTextStyles.body),
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
          const Text("Couldn't load this."),
          const SizedBox(height: FlcSpace.sm),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
