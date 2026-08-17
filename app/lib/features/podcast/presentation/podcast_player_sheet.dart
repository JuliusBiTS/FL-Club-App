import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';

import '../audio/podcast_audio_handler.dart';

/// Full player — art, seek bar, play/pause, ±10s skip. Playback itself
/// lives in the handler (survives this sheet closing, briefing §9.8
/// background playback), so this is purely a view over its streams.
class PodcastPlayerSheet extends StatelessWidget {
  const PodcastPlayerSheet({required this.handler, super.key});

  final PodcastAudioHandler handler;

  static void show(BuildContext context, PodcastAudioHandler handler) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PodcastPlayerSheet(handler: handler),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FlcSpace.lg),
        child: StreamBuilder<MediaItem?>(
          stream: handler.mediaItem,
          builder: (context, mediaSnapshot) {
            final mediaItem = mediaSnapshot.data;
            if (mediaItem == null) return const SizedBox(height: 200);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(FlcRadius.card),
                  child: SizedBox(
                    width: 160,
                    height: 160,
                    child: mediaItem.artUri == null
                        ? ColoredBox(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.podcasts, size: 48),
                          )
                        : CachedNetworkImage(imageUrl: mediaItem.artUri.toString(), fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: FlcSpace.md),
                Text(mediaItem.title, style: FlcTextStyles.h3, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: FlcSpace.md),
                _SeekBar(handler: handler, duration: mediaItem.duration ?? handler.duration ?? Duration.zero),
                const SizedBox(height: FlcSpace.sm),
                _Controls(handler: handler),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.handler, required this.duration});

  final PodcastAudioHandler handler;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: handler.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final totalMs = duration.inMilliseconds;
        final value = totalMs <= 0 ? 0.0 : (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
        return Column(
          children: <Widget>[
            Slider(
              value: value,
              onChanged: totalMs <= 0
                  ? null
                  : (v) => handler.seek(Duration(milliseconds: (v * totalMs).round())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FlcSpace.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(_format(position), style: FlcTextStyles.caption.copyWith(color: FlcColors.slate)),
                  Text(_format(duration), style: FlcTextStyles.caption.copyWith(color: FlcColors.slate)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.handler});

  final PodcastAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton(
              iconSize: 32,
              icon: const Icon(Icons.replay_10),
              onPressed: () => handler.seek(handler.position - const Duration(seconds: 10)),
            ),
            const SizedBox(width: FlcSpace.md),
            IconButton(
              iconSize: 56,
              icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
              onPressed: playing ? handler.pause : handler.play,
            ),
            const SizedBox(width: FlcSpace.md),
            IconButton(
              iconSize: 32,
              icon: const Icon(Icons.forward_10),
              onPressed: () => handler.seek(handler.position + const Duration(seconds: 10)),
            ),
          ],
        );
      },
    );
  }
}
