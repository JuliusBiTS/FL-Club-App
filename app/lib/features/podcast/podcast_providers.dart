import 'package:flc_core/flc_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local_db/app_database_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import 'audio/podcast_audio_handler.dart';
import 'data/podcast_local_data_source.dart';
import 'data/podcast_remote_data_source.dart';
import 'data/podcast_repository_impl.dart';
import 'domain/podcast_repository.dart';

final Provider<PodcastRemoteDataSource> _podcastRemoteDataSourceProvider = Provider<PodcastRemoteDataSource>((ref) {
  return PodcastRemoteDataSource(ref.watch(supabaseClientProvider));
});

final Provider<PodcastLocalDataSource> _podcastLocalDataSourceProvider = Provider<PodcastLocalDataSource>((ref) {
  return PodcastLocalDataSource(ref.watch(appDatabaseProvider));
});

final Provider<PodcastRepository> podcastRepositoryProvider = Provider<PodcastRepository>((ref) {
  return PodcastRepositoryImpl(
    ref.watch(_podcastRemoteDataSourceProvider),
    ref.watch(_podcastLocalDataSourceProvider),
    () => ref.read(currentUserProvider)?.id,
  );
});

/// Overridden in main.dart once AudioService.init() has produced the real
/// handler — see the class doc comment on PodcastAudioHandler. Never read
/// before then; nothing in the widget tree exists before that override is
/// in place.
final Provider<PodcastAudioHandler> podcastAudioHandlerProvider = Provider<PodcastAudioHandler>((ref) {
  throw UnimplementedError('podcastAudioHandlerProvider must be overridden with the AudioService.init() result');
});

final FutureProvider<Map<String, PlaybackProgressModel>> playbackProgressProvider =
    FutureProvider<Map<String, PlaybackProgressModel>>((ref) {
  ref.watch(currentUserProvider); // re-fetch on sign-in/out
  return ref.watch(podcastRepositoryProvider).getPlaybackProgress();
});
