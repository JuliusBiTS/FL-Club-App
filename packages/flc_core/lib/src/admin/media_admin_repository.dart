import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/media_post.dart';

/// Manual media (YouTube video) management, and manual sync triggers for
/// the two Edge Functions that otherwise only run on their own hourly
/// pg_cron schedule — feedback: "how do you edit the media tab? Any way
/// for an admin to do changes there? Maybe a manual way to add podcast
/// links and YT videos?"
///
/// Deliberately does NOT touch podcast_episodes: that table is entirely
/// owned by podcast-sync's upsert-by-guid from the RSS feed (briefing —
/// "we consume the existing public RSS feed directly"). Adding a manual
/// row there with no guid would sit oddly alongside synced ones and could
/// collide with the sync's own upsert key; a "sync now" button is the
/// right manual lever for podcasts, not a hand-added row.
class MediaAdminRepository {
  MediaAdminRepository(this._client);

  final SupabaseClient _client;

  Future<List<MediaPostModel>> listMediaPosts() async {
    final rows = await _client.from('media_posts').select().order('published_at', ascending: false);
    return rows.map(MediaPostModel.fromJson).toList();
  }

  /// [youtubeIdOrUrl] accepts either a bare video id or a full youtube.com/
  /// youtu.be URL — extracted here so staff can just paste whatever's in
  /// their browser bar.
  Future<void> addYoutubeVideo({
    required String youtubeIdOrUrl,
    required String title,
    String? description,
    required DateTime publishedAt,
    bool isLive = false,
  }) async {
    final String id = extractYoutubeId(youtubeIdOrUrl);
    await _client.from('media_posts').insert(<String, dynamic>{
      'source': 'youtube',
      'external_id': id,
      'title': title.trim(),
      'description': (description ?? '').trim().isEmpty ? null : description!.trim(),
      // Same convention the earlier hand-seeded rows used — no API key
      // needed for a thumbnail, YouTube serves these publicly by id.
      'thumbnail_url': 'https://img.youtube.com/vi/$id/hqdefault.jpg',
      'published_at': publishedAt.toUtc().toIso8601String(),
      'is_live': isLive,
    });
  }

  Future<void> deleteMediaPost(String id) async {
    await _client.from('media_posts').delete().eq('id', id);
  }

  /// Runs podcast-sync/wordpress-sync on demand — e.g. right after
  /// publishing a new episode, without waiting for the next hourly
  /// pg_cron tick. Both functions are public/unauthenticated
  /// (verify_jwt: false) since they only ever pull from a public feed.
  Future<int> triggerPodcastSync() async {
    final response = await _client.functions.invoke('podcast-sync');
    final data = response.data as Map<String, dynamic>;
    return (data['upserted'] as num?)?.toInt() ?? 0;
  }

  Future<void> triggerWordpressSync() async {
    await _client.functions.invoke('wordpress-sync');
  }

  /// Accepts `youtu.be/<id>`, `youtube.com/watch?v=<id>`, `youtube.com/shorts/<id>`,
  /// or a bare id — whatever's easiest to paste from a browser bar.
  static String extractYoutubeId(String input) {
    final String trimmed = input.trim();
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return trimmed; // already a bare id
    if (uri.host.contains('youtu.be')) return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : trimmed;
    if (uri.pathSegments.contains('shorts')) {
      final int i = uri.pathSegments.indexOf('shorts');
      return i + 1 < uri.pathSegments.length ? uri.pathSegments[i + 1] : trimmed;
    }
    return uri.queryParameters['v'] ?? trimmed;
  }
}
