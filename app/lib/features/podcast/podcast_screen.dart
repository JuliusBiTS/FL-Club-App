import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/membership_handle_visibility.dart';
import 'audio/podcast_audio_handler.dart';
import 'podcast_providers.dart';
import 'presentation/episode_card.dart';
import 'presentation/podcast_feed_controller.dart';
import 'presentation/podcast_player_sheet.dart';

/// Episode list + player — briefing §9.8. RSS-sourced, background playback
/// via just_audio + audio_service, no account required to listen; signed-in
/// listeners additionally get resume-from-position via playback_progress.
class PodcastScreen extends ConsumerStatefulWidget {
  const PodcastScreen({super.key});

  @override
  ConsumerState<PodcastScreen> createState() => _PodcastScreenState();
}

class _PodcastScreenState extends ConsumerState<PodcastScreen> {
  Timer? _progressTimer;
  StreamSubscription<PlaybackState>? _playbackSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  String? _trackedEpisodeId;

  @override
  void initState() {
    super.initState();
    // The mini player bar below claims the same screen real estate as the
    // persistent "Become a member" handle AppShell draws on top of every
    // tab (briefing §9.6) — same conflict event_detail_screen's "Get
    // tickets" bar has, same fix: claim the space via
    // showMembershipHandleProvider while something is loaded, release it
    // when playback is stopped. See that provider's doc comment.
    _mediaItemSub = ref.read(podcastAudioHandlerProvider).mediaItem.listen((mediaItem) {
      ref.read(showMembershipHandleProvider.notifier).state = mediaItem == null;
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _playbackSub?.cancel();
    _mediaItemSub?.cancel();
    ref.read(showMembershipHandleProvider.notifier).state = true;
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
    final progressAsync = ref.watch(playbackProgressProvider);
    final handler = ref.watch(podcastAudioHandlerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Podcast')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: episodesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _ErrorState(onRetry: () => ref.read(podcastFeedControllerProvider.notifier).refresh()),
              data: (episodes) {
                if (episodes.isEmpty) return const _EmptyState();
                final progress = progressAsync.valueOrNull ?? const <String, PlaybackProgressModel>{};
                return RefreshIndicator(
                  onRefresh: () => ref.read(podcastFeedControllerProvider.notifier).refresh(),
                  child: ListView.builder(
                    itemCount: episodes.length,
                    itemBuilder: (context, index) {
                      final episode = episodes[index];
                      return EpisodeCard(
                        episode: episode,
                        progress: progress[episode.id],
                        onTap: () => _playEpisode(episode),
                      );
                    },
                  ),
                );
              },
            ),
          ),
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
            Icon(Icons.podcasts_outlined, size: 40, color: FlcColors.slate),
            SizedBox(height: FlcSpace.sm),
            Text('No episodes yet — check back soon.', textAlign: TextAlign.center, style: FlcTextStyles.body),
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
          const Text("Couldn't load episodes."),
          const SizedBox(height: FlcSpace.sm),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
