import 'package:flc_core/flc_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A direct Supabase read, same shape as loyalty_repository.dart —
/// media_posts is publicly readable (RLS: `for select using (true)`, no
/// account needed, briefing feedback 2026-08-24) and small enough that a
/// view/cache layer would be premature. Real-time sync from YouTube is a
/// separate concern (a scheduled Edge Function, once API access exists —
/// see docs/OPEN_QUESTIONS.md); this repository doesn't know or care
/// whether the rows it reads were synced or hand-seeded.
class MediaRepository {
  MediaRepository(this._client);

  final SupabaseClient _client;

  Future<List<MediaPostModel>> getPosts() async {
    final rows = await _client.from('media_posts').select().order('published_at', ascending: false);
    return (rows as List<dynamic>).map((r) => MediaPostModel.fromJson(r as Map<String, dynamic>)).toList();
  }
}
