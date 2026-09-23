import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/media_post.dart';

/// A hand-added podcast episode or article, as listed on the Content screen.
class ManualItem {
  const ManualItem({required this.id, required this.title, required this.publishedAt});

  final String id;
  final String title;
  final DateTime publishedAt;

  factory ManualItem.fromRow(Map<String, dynamic> r) => ManualItem(
        id: r['id'] as String,
        title: r['title'] as String,
        publishedAt: DateTime.parse(r['published_at'] as String),
      );
}

/// Manual media management (YouTube videos, podcast episodes, articles), and
/// manual sync triggers for the two Edge Functions that otherwise only run on
/// their own hourly pg_cron schedule. Hand-added podcasts/articles live in the
/// same tables as synced ones but are namespaced so they can never collide
/// with a sync (see the section below).
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

  // Hand-added podcast episodes and articles ---------------------------------
  //
  // Additive only. The syncs upsert by guid / wp_post_id and never delete, so
  // hand-added rows are told apart by a `manual:` guid prefix (podcasts) and a
  // null wp_post_id (articles). Only those can be listed or removed here —
  // synced rows are never touched from this screen.

  Future<List<ManualItem>> listManualPodcasts() async {
    final rows = await _client
        .from('podcast_episodes')
        .select('id, title, published_at')
        .like('guid', 'manual:%')
        .order('published_at', ascending: false);
    return rows.map(ManualItem.fromRow).toList();
  }

  Future<void> addPodcastEpisode({
    required String title,
    required String audioUrl,
    String? description,
    String? imageUrl,
    required DateTime publishedAt,
  }) async {
    final Uri? uri = Uri.tryParse(audioUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.host.contains('.')) {
      throw const FormatException('Enter the full audio link, starting with https://');
    }
    await _client.from('podcast_episodes').insert(<String, dynamic>{
      // Random suffix keeps it clear of any guid the RSS sync will ever use.
      'guid': 'manual:${DateTime.now().microsecondsSinceEpoch}-${audioUrl.hashCode.abs()}',
      'title': title.trim(),
      'audio_url': audioUrl.trim(),
      'description_html': _paragraphs(description),
      'image_url': _blankToNull(imageUrl),
      'published_at': publishedAt.toUtc().toIso8601String(),
    });
  }

  Future<void> deletePodcastEpisode(String id) async {
    await _client.from('podcast_episodes').delete().eq('id', id).like('guid', 'manual:%');
  }

  Future<List<ManualItem>> listManualArticles() async {
    final rows = await _client
        .from('articles')
        .select('id, title, published_at')
        .isFilter('wp_post_id', null)
        .order('published_at', ascending: false);
    return rows.map(ManualItem.fromRow).toList();
  }

  Future<void> addArticle({
    required String title,
    required String body,
    String? excerpt,
    String? heroImageUrl,
    String? authorName,
    String? linkUrl,
    required DateTime publishedAt,
  }) async {
    final String slug = '${_slugify(title)}-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    await _client.from('articles').insert(<String, dynamic>{
      'slug': slug,
      'title': title.trim(),
      'excerpt': _blankToNull(excerpt),
      'content_html': _paragraphs(body),
      'hero_image_url': _blankToNull(heroImageUrl),
      'author_name': _blankToNull(authorName),
      'canonical_url': _blankToNull(linkUrl) ?? 'https://www.frontlineclub.com',
      'published_at': publishedAt.toUtc().toIso8601String(),
    });
  }

  Future<void> deleteArticle(String id) async {
    await _client.from('articles').delete().eq('id', id).isFilter('wp_post_id', null);
  }

  static String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  static String _slugify(String s) {
    final String slug = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'post' : (slug.length > 60 ? slug.substring(0, 60) : slug);
  }

  /// Plain text in, minimal safe HTML out: escaped, blank line = new paragraph.
  static String? _paragraphs(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    String esc(String v) => v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    return text
        .trim()
        .split(RegExp(r'\n\s*\n'))
        .map((String p) => '<p>${esc(p.trim()).replaceAll('\n', '<br>')}</p>')
        .join();
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
