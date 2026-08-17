import 'package:audio_service/audio_service.dart';
import 'package:flc_core/flc_core.dart';
import 'package:just_audio/just_audio.dart';

/// Bridges just_audio (actual decode/playback) to audio_service (lock
/// screen + notification controls, briefing §9.8 "background playback").
/// One handler instance for the app's lifetime, created by AudioService.init
/// in main.dart before the widget tree exists — see podcast_providers.dart
/// for how it's threaded into Riverpod via an override.
class PodcastAudioHandler extends BaseAudioHandler with SeekHandler {
  PodcastAudioHandler() {
    _player.playbackEventStream.listen(_broadcastState, onError: (Object e, StackTrace st) {});
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onCompleted?.call();
    });
  }

  final AudioPlayer _player = AudioPlayer();
  void Function()? _onCompleted;

  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  Stream<Duration> get positionStream => _player.positionStream;

  Future<void> loadAndPlay(
    PodcastEpisodeModel episode, {
    Duration startAt = Duration.zero,
    required void Function() onCompleted,
  }) async {
    _onCompleted = onCompleted;
    mediaItem.add(MediaItem(
      id: episode.id,
      title: episode.title,
      album: 'Podcast',
      artUri: episode.imageUrl == null ? null : Uri.tryParse(episode.imageUrl!),
      duration: episode.durationSeconds == null ? null : Duration(seconds: episode.durationSeconds!),
    ));
    await _player.setAudioSource(AudioSource.uri(Uri.parse(episode.audioUrl)));
    if (startAt > Duration.zero) {
      await _player.seek(startAt);
    }
    await play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    mediaItem.add(null);
    _onCompleted = null;
    return super.stop();
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: <MediaControl>[
        MediaControl.rewind,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.fastForward,
      ],
      systemActions: const <MediaAction>{MediaAction.seek},
      androidCompactActionIndices: const <int>[0, 1, 3],
      processingState: const <ProcessingState, AudioProcessingState>{
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    ));
  }
}
