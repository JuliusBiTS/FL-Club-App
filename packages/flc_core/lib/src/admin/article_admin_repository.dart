import 'package:supabase_flutter/supabase_flutter.dart';

/// An article as the admin sees it — includes drafts, and knows whether it
/// came from the website sync (read-only here: an edit would be overwritten
/// on the next sync) or was written by hand (fully editable).
class AdminArticle {
  const AdminArticle({
    required this.id,
    required this.title,
    required this.publishedAt,
    required this.isDraft,
    required this.fromWebsite,
    this.excerpt,
    this.contentHtml,
    this.heroImageUrl,
    this.authorName,
    this.categories = const <String>[],
    this.linkUrl,
  });

  final String id;
  final String title;
  final DateTime publishedAt;
  final bool isDraft;
  final bool fromWebsite;
  final String? excerpt;
  final String? contentHtml;
  final String? heroImageUrl;
  final String? authorName;
  final List<String> categories;
  final String? linkUrl;

  factory AdminArticle.fromRow(Map<String, dynamic> r) => AdminArticle(
        id: r['id'] as String,
        title: r['title'] as String,
        publishedAt: DateTime.parse(r['published_at'] as String),
        isDraft: r['status'] == 'draft',
        fromWebsite: r['wp_post_id'] != null,
        excerpt: r['excerpt'] as String?,
        contentHtml: r['content_html'] as String?,
        heroImageUrl: r['hero_image_url'] as String?,
        authorName: r['author_name'] as String?,
        categories: ((r['categories'] as List?) ?? const <dynamic>[]).cast<String>(),
        linkUrl: r['canonical_url'] as String?,
      );
}

/// Stories and blog articles: list, write, edit, draft/publish, delete.
/// Only hand-written articles (no wp_post_id) can be changed or removed —
/// enforced here in every query, not just hidden in the UI.
class ArticleAdminRepository {
  ArticleAdminRepository(this._client);

  final SupabaseClient _client;

  static const String _defaultLink = 'https://www.frontlineclub.com';

  Future<List<AdminArticle>> list() async {
    final rows = await _client
        .from('articles')
        .select('id, wp_post_id, title, excerpt, content_html, hero_image_url, author_name, categories, canonical_url, published_at, status')
        .order('published_at', ascending: false)
        .limit(300);
    return rows.map(AdminArticle.fromRow).toList();
  }

  /// [existing] null = create.
  Future<void> save({
    AdminArticle? existing,
    required String title,
    required String body,
    String? excerpt,
    String? heroImageUrl,
    String? authorName,
    String? linkUrl,
    required List<String> categories,
    required DateTime publishedAt,
    required bool draft,
  }) async {
    if (title.trim().isEmpty) throw const FormatException('Give the article a title.');
    if (body.trim().isEmpty) throw const FormatException('The article needs some text.');
    final String? link = _blank(linkUrl);
    if (link != null) {
      final Uri? u = Uri.tryParse(link);
      if (u == null || !(u.scheme == 'https' || u.scheme == 'http') || !u.host.contains('.')) {
        throw const FormatException('The link to the original must start with https://');
      }
    }
    final Map<String, dynamic> row = <String, dynamic>{
      'title': title.trim(),
      'excerpt': _blank(excerpt),
      'content_html': textToHtml(body),
      'hero_image_url': _blank(heroImageUrl),
      'author_name': _blank(authorName),
      'categories': categories,
      'canonical_url': link ?? _defaultLink,
      'published_at': publishedAt.toUtc().toIso8601String(),
      'status': draft ? 'draft' : 'published',
    };
    if (existing == null) {
      row['slug'] = '${_slugify(title)}-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
      await _client.from('articles').insert(row);
    } else {
      await _client.from('articles').update(row).eq('id', existing.id).isFilter('wp_post_id', null);
    }
  }

  Future<void> delete(String id) async {
    await _client.from('articles').delete().eq('id', id).isFilter('wp_post_id', null);
  }

  static String? _blank(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  static String _slugify(String s) {
    final String slug = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'post' : (slug.length > 60 ? slug.substring(0, 60) : slug);
  }

  /// Plain text in, minimal safe HTML out: escaped, blank line = new paragraph.
  static String textToHtml(String text) {
    String esc(String v) => v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    return text
        .trim()
        .split(RegExp(r'\n\s*\n'))
        .map((String p) => '<p>${esc(p.trim()).replaceAll('\n', '<br>')}</p>')
        .join();
  }

  /// Inverse of [textToHtml], so a hand-written article can be edited again.
  static String htmlToText(String? html) {
    if (html == null) return '';
    return html
        .replaceAll(RegExp(r'</p>\s*<p>'), '\n\n')
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .trim();
  }
}
