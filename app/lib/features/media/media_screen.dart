import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'media_providers.dart';
import 'presentation/media_post_card.dart';

/// Briefing feedback (2026-08-24): a feed of the club's own video content.
/// YouTube-only for now — see media_repository.dart and
/// docs/OPEN_QUESTIONS.md for why Instagram isn't merged in yet.
///
/// Playback opens the real YouTube app rather than an in-app embedded
/// player — a WebView-based iframe embed hit YouTube's own anti-scraping
/// checks (error 152/153) with no reliable fix, regardless of that
/// video's own embedding settings. Every real phone has the YouTube app
/// (or falls back to the browser), so this is the more reliable choice,
/// not just the simpler one.
class MediaScreen extends ConsumerWidget {
  const MediaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(mediaFeedControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Media')),
      body: postsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorState(onRetry: () => ref.read(mediaFeedControllerProvider.notifier).refresh()),
        data: (posts) {
          if (posts.isEmpty) return const _EmptyState();
          return RefreshIndicator(
            onRefresh: () => ref.read(mediaFeedControllerProvider.notifier).refresh(),
            child: ListView.builder(
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                return MediaPostCard(
                  post: post,
                  onTap: () => launchUrl(
                    Uri.parse('https://www.youtube.com/watch?v=${post.externalId}'),
                    mode: LaunchMode.externalApplication,
                  ),
                );
              },
            ),
          );
        },
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
            Icon(Icons.video_library_outlined, size: 40, color: FlcColors.slate),
            SizedBox(height: FlcSpace.sm),
            Text('No videos yet — check back soon.', textAlign: TextAlign.center, style: FlcTextStyles.body),
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
          const Text("Couldn't load videos."),
          const SizedBox(height: FlcSpace.sm),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
