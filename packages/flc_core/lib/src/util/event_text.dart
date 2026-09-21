/// Text helpers for the event editor.
///
/// Producers write descriptions in plain text with a few light marks
/// (`**bold**`, `*italic*`, `[text](https://…)`, `- ` bullets, `## ` headings)
/// through a toolbar — nobody types HTML. The markdown is kept in
/// `events.description_md`; the HTML in `events.description_html` is
/// *generated* from it on every save, using only the tags the WordPress plugin
/// and the app already allow (p, br, strong, em, ul, ol, li, a, blockquote,
/// h2, h3). Everything is HTML-escaped first, and links are limited to
/// http(s)/mailto, so nothing typed into the box can inject markup.
abstract final class EventText {
  static String markdownToHtml(String source) {
    final String text = source.replaceAll('\r\n', '\n').trim();
    if (text.isEmpty) return '';

    final StringBuffer out = StringBuffer();
    for (final String block in text.split(RegExp(r'\n{2,}'))) {
      final List<String> lines = block
          .split('\n')
          .map((String l) => l.trimRight())
          .where((String l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;

      if (lines.every((String l) => l.trimLeft().startsWith('- '))) {
        out.write('<ul>');
        for (final String l in lines) {
          out.write('<li>${_inline(l.trimLeft().substring(2))}</li>');
        }
        out.write('</ul>');
      } else if (lines.length == 1 && lines.first.startsWith('### ')) {
        out.write('<h3>${_inline(lines.first.substring(4))}</h3>');
      } else if (lines.length == 1 && lines.first.startsWith('## ')) {
        out.write('<h2>${_inline(lines.first.substring(3))}</h2>');
      } else if (lines.every((String l) => l.startsWith('> '))) {
        out.write('<blockquote><p>${lines.map((String l) => _inline(l.substring(2))).join('<br>')}</p></blockquote>');
      } else {
        out.write('<p>${lines.map(_inline).join('<br>')}</p>');
      }
    }
    return out.toString();
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _inline(String raw) {
    String h = _escape(raw);
    h = h.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\((https?://[^\s)]+|mailto:[^\s)]+)\)'),
      (Match m) => '<a href="${m[2]}">${m[1]}</a>',
    );
    h = h.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (Match m) => '<strong>${m[1]}</strong>');
    h = h.replaceAllMapped(RegExp(r'(?<![*\w])\*(?!\s)(.+?)(?<!\s)\*(?![*\w])'), (Match m) => '<em>${m[1]}</em>');
    return h;
  }

  /// Best-effort plain text from HTML — the starting point in the editor for
  /// events created before description_md existed (seed data, Eventbrite).
  static String stripHtml(String html) {
    String t = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(p|h2|h3|blockquote)>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '- ')
        .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    t = t
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
    return t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// "Afghanistan 2026" + 9 Sep 2026 → "afghanistan-2026-20260909". The date
  /// suffix keeps recurring formats ("World Briefing") from colliding.
  static String slugify(String title, DateTime? date) {
    String base = title
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (base.length > 60) base = base.substring(0, 60).replaceAll(RegExp(r'-+$'), '');
    if (base.isEmpty) base = 'event';
    if (date == null) return base;
    final String d = '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    return '$base-$d';
  }
}
