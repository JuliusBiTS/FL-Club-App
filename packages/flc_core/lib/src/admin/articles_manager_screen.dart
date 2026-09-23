import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../events_admin/event_admin_repository.dart';
import '../events_admin/widgets/editor_widgets.dart';
import '../theme/flc_colors.dart';
import '../theme/flc_spacing.dart';
import '../theme/flc_typography.dart';
import 'article_admin_repository.dart';

enum _ArticleFilter { all, published, drafts, handWritten }

/// Stories and blog articles — the same idea as the events manager: a list
/// you can search and filter, a "New article" button, and a proper editor
/// page (picture, text, draft/publish) rather than a pop-up.
class ArticlesManagerScreen extends StatefulWidget {
  const ArticlesManagerScreen({required this.repository, required this.imageRepository, this.embedded = false, super.key});

  final ArticleAdminRepository repository;

  /// Only used for uploading pictures (same public image bucket as events).
  final EventAdminRepository imageRepository;
  final bool embedded;

  @override
  State<ArticlesManagerScreen> createState() => _ArticlesManagerScreenState();
}

class _ArticlesManagerScreenState extends State<ArticlesManagerScreen> {
  late Future<List<AdminArticle>> _articles = widget.repository.list();
  _ArticleFilter _filter = _ArticleFilter.all;
  String _search = '';

  void _reload() => setState(() => _articles = widget.repository.list());

  Future<void> _open([AdminArticle? article]) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ArticleEditorScreen(repository: widget.repository, imageRepository: widget.imageRepository, article: article),
      ),
    );
    if (changed == true) _reload();
  }

  bool _matches(AdminArticle a) {
    if (_search.isNotEmpty && !a.title.toLowerCase().contains(_search.toLowerCase())) return false;
    return switch (_filter) {
      _ArticleFilter.all => true,
      _ArticleFilter.published => !a.isDraft,
      _ArticleFilter.drafts => a.isDraft,
      _ArticleFilter.handWritten => !a.fromWebsite,
    };
  }

  @override
  Widget build(BuildContext context) {
    final double gutter = widget.embedded ? FlcSpace.xl : FlcSpace.md;

    final Widget body = ListView(
      padding: EdgeInsets.all(gutter),
      children: <Widget>[
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (widget.embedded) ...<Widget>[
                  Text('Stories & articles', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: FlcSpace.xs),
                ],
                Text(
                  'Write stories and blog posts for the app\'s Read tab. Articles from the website appear here too but are managed on the website.',
                  style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)),
                ),
                const SizedBox(height: FlcSpace.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search articles'),
                        onChanged: (String v) => setState(() => _search = v.trim()),
                      ),
                    ),
                    const SizedBox(width: FlcSpace.sm),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                      onPressed: () => _open(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New article'),
                    ),
                  ],
                ),
                const SizedBox(height: FlcSpace.sm),
                Wrap(
                  spacing: FlcSpace.xs,
                  children: <Widget>[
                    for (final (_ArticleFilter f, String label) in <(_ArticleFilter, String)>[
                      (_ArticleFilter.all, 'All'),
                      (_ArticleFilter.published, 'Published'),
                      (_ArticleFilter.drafts, 'Drafts'),
                      (_ArticleFilter.handWritten, 'Written here'),
                    ])
                      ChoiceChip(label: Text(label), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
                  ],
                ),
                const SizedBox(height: FlcSpace.md),
                FutureBuilder<List<AdminArticle>>(
                  future: _articles,
                  builder: (BuildContext context, AsyncSnapshot<List<AdminArticle>> snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(padding: EdgeInsets.all(FlcSpace.md), child: LinearProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Text(
                        "Couldn't load articles. ${EventAdminRepository.describeError(snap.error!)}",
                        style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.errorAccent(context)),
                      );
                    }
                    final List<AdminArticle> items = (snap.data ?? const <AdminArticle>[]).where(_matches).toList();
                    if (items.isEmpty) {
                      return Text('Nothing here yet.', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)));
                    }
                    return Card(
                      child: Column(
                        children: <Widget>[
                          for (final AdminArticle a in items)
                            ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: SizedBox(
                                  width: 64,
                                  height: 40,
                                  child: a.heroImageUrl == null
                                      ? const ColoredBox(color: FlcColors.line, child: Icon(Icons.article_outlined))
                                      : Image.network(
                                          a.heroImageUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) => const ColoredBox(color: FlcColors.line, child: Icon(Icons.broken_image_outlined)),
                                        ),
                                ),
                              ),
                              title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                <String>[
                                  DateFormat('d MMM yyyy').format(a.publishedAt.toLocal()),
                                  if (a.isDraft) 'Draft',
                                  a.fromWebsite ? 'From the website' : 'Written here',
                                  ...a.categories,
                                ].join(' · '),
                              ),
                              trailing: Icon(a.fromWebsite ? Icons.lock_outline : Icons.edit_outlined, size: 18),
                              onTap: a.fromWebsite
                                  ? () => ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('This one comes from the website — edit it there and it will update here.')),
                                      )
                                  : () => _open(a),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Stories & articles')), body: body);
  }
}

class ArticleEditorScreen extends StatefulWidget {
  const ArticleEditorScreen({required this.repository, required this.imageRepository, this.article, super.key});

  final ArticleAdminRepository repository;
  final EventAdminRepository imageRepository;
  final AdminArticle? article;

  @override
  State<ArticleEditorScreen> createState() => _ArticleEditorScreenState();
}

class _ArticleEditorScreenState extends State<ArticleEditorScreen> {
  static const List<String> _kinds = <String>['Story', 'Blog'];

  late final TextEditingController _title = TextEditingController(text: widget.article?.title ?? '');
  late final TextEditingController _excerpt = TextEditingController(text: widget.article?.excerpt ?? '');
  late final TextEditingController _body = TextEditingController(text: ArticleAdminRepository.htmlToText(widget.article?.contentHtml));
  late final TextEditingController _author = TextEditingController(text: widget.article?.authorName ?? '');
  late final TextEditingController _link = TextEditingController(
    text: widget.article?.linkUrl == 'https://www.frontlineclub.com' ? '' : (widget.article?.linkUrl ?? ''),
  );
  late String? _image = widget.article?.heroImageUrl;
  late DateTime _published = widget.article?.publishedAt.toLocal() ?? DateTime.now();
  late String _kind = (widget.article?.categories.contains('Story') ?? false) ? 'Story' : 'Blog';
  late final bool _draft = widget.article?.isDraft ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _excerpt.dispose();
    _body.dispose();
    _author.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _save({bool? asDraft}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.save(
        existing: widget.article,
        title: _title.text,
        body: _body.text,
        excerpt: _excerpt.text,
        heroImageUrl: _image,
        authorName: _author.text,
        linkUrl: _link.text,
        // Keep any other categories the article already had; just swap the type.
        categories: <String>[
          _kind,
          ...?widget.article?.categories.where((String c) => !_kinds.contains(c)),
        ],
        publishedAt: _published,
        draft: asDraft ?? _draft,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is FormatException ? e.message : EventAdminRepository.describeError(e);
      });
    }
  }

  Future<void> _autoFill() async {
    final ExtractedArticle? x = await showDialog<ExtractedArticle>(
      context: context,
      builder: (BuildContext ctx) => _PasteDraftDialog(repository: widget.repository),
    );
    if (x == null || !mounted) return;
    final List<String> filled = <String>[];
    final List<String> kept = <String>[];
    void fill(String label, TextEditingController c, String? value) {
      if (value == null) return;
      if (c.text.trim().isEmpty) {
        c.text = value;
        filled.add(label);
      } else {
        kept.add(label);
      }
    }

    setState(() {
      fill('title', _title, x.title);
      fill('summary', _excerpt, x.excerpt);
      fill('text', _body, x.body);
      fill('author', _author, x.authorName);
      fill('link', _link, x.linkUrl);
      if (widget.article == null) {
        if (x.kind != null && _kinds.contains(x.kind)) {
          _kind = x.kind!;
          filled.add('type');
        }
        if (x.publishedOn != null && !x.publishedOn!.isAfter(DateTime.now())) {
          _published = x.publishedOn!;
          filled.add('date');
        }
      }
    });
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Auto-fill'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(filled.isEmpty ? 'Couldn\'t find anything new to fill in.' : 'Filled in: ${filled.join(', ')}.'),
                if (kept.isNotEmpty) ...<Widget>[
                  const SizedBox(height: FlcSpace.sm),
                  Text('Left alone (already had something): ${kept.join(', ')}.', style: TextStyle(color: FlcColors.secondary(ctx))),
                ],
                if (x.notes.isNotEmpty) ...<Widget>[
                  const SizedBox(height: FlcSpace.sm),
                  Text('Worth checking', style: FlcTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: FlcColors.warning)),
                  for (final String n in x.notes) Text('• $n'),
                ],
                const SizedBox(height: FlcSpace.sm),
                const Text('Add a picture below, then check everything before publishing.', style: FlcTextStyles.bodySmall),
              ],
            ),
          ),
        ),
        actions: <Widget>[TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _delete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Delete this article?'),
        content: const Text('It will disappear from the app for good.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repository.delete(widget.article!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = EventAdminRepository.describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isNew = widget.article == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New article' : 'Edit article'),
        actions: <Widget>[
          if (!isNew) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: _saving ? null : _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(FlcSpace.md),
        children: <Widget>[
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SectionCard(
                    title: 'Paste a draft to auto-fill',
                    subtitle: 'Got the whole piece in a document or an email? Paste it all in — it sorts out the title, summary, text, type, author and date. '
                        'The AI writes nothing and changes nothing: every word comes straight from what you pasted (it only points out the headline, byline and so on, and cuts the email wrapper). It only fills blank fields, and nothing is saved until you press Publish or Save as draft.',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: FlcColors.accent(context)),
                        icon: const Icon(Icons.auto_fix_high_outlined),
                        label: const Text('Paste a draft'),
                        onPressed: _saving ? null : _autoFill,
                      ),
                    ),
                  ),
                  SectionCard(
                    title: 'Picture',
                    subtitle: 'Shown at the top of the article and on its card. Without one, the first picture in the text (or the club logo) is used.',
                    child: ImageSlot(
                      repository: widget.imageRepository,
                      url: _image,
                      onChanged: (String? v) => setState(() => _image = v),
                      enabled: !_saving,
                    ),
                  ),
                  SectionCard(
                    title: 'The article',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SegmentedButton<String>(
                          segments: <ButtonSegment<String>>[for (final String k in _kinds) ButtonSegment<String>(value: k, label: Text(k))],
                          selected: <String>{_kind},
                          onSelectionChanged: (Set<String> s) => setState(() => _kind = s.first),
                        ),
                        const SizedBox(height: FlcSpace.sm),
                        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
                        const SizedBox(height: FlcSpace.sm),
                        TextField(
                          controller: _excerpt,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(labelText: 'Short summary (optional)', helperText: 'The line under the title on the article card'),
                        ),
                        const SizedBox(height: FlcSpace.sm),
                        TextField(
                          controller: _body,
                          minLines: 10,
                          maxLines: 40,
                          decoration: const InputDecoration(labelText: 'Text', helperText: 'Leave a blank line between paragraphs.', alignLabelWithHint: true),
                        ),
                      ],
                    ),
                  ),
                  SectionCard(
                    title: 'Details',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        TextField(controller: _author, decoration: const InputDecoration(labelText: 'Author (optional)')),
                        const SizedBox(height: FlcSpace.sm),
                        TextField(
                          controller: _link,
                          decoration: const InputDecoration(labelText: 'Link to the original (optional)', hintText: 'https://…'),
                        ),
                        const SizedBox(height: FlcSpace.xs),
                        Row(
                          children: <Widget>[
                            Expanded(child: Text('Date ${DateFormat('d MMM yyyy').format(_published)}', style: FlcTextStyles.bodySmall)),
                            TextButton(
                              onPressed: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: _published,
                                  firstDate: DateTime(2010),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (picked != null) setState(() => _published = picked);
                              },
                              child: const Text('Change'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: FlcSpace.sm),
                      child: Text(_error!, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.errorAccent(context))),
                    ),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: FlcColors.accent(context)),
                          onPressed: _saving ? null : () => _save(asDraft: true),
                          child: const Text('Save as draft'),
                        ),
                      ),
                      const SizedBox(width: FlcSpace.sm),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                          onPressed: _saving ? null : () => _save(asDraft: false),
                          child: _saving
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(!isNew && !widget.article!.isDraft ? 'Save changes' : 'Publish'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FlcSpace.xl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasteDraftDialog extends StatefulWidget {
  const _PasteDraftDialog({required this.repository});

  final ArticleAdminRepository repository;

  @override
  State<_PasteDraftDialog> createState() => _PasteDraftDialogState();
}

class _PasteDraftDialogState extends State<_PasteDraftDialog> {
  final TextEditingController _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_text.text.trim().length < 20) {
      setState(() => _error = 'Paste a bit more — a few sentences at least.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ExtractedArticle x = await widget.repository.extractDetails(_text.text.trim());
      if (mounted) Navigator.pop(context, x);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = EventAdminRepository.describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paste a draft'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Paste the whole piece — headline, text, byline, anything. Your wording is never changed and nothing is generated.', style: FlcTextStyles.bodySmall),
            const SizedBox(height: FlcSpace.sm),
            TextField(
              controller: _text,
              enabled: !_busy,
              minLines: 10,
              maxLines: 16,
              maxLength: 30000,
              decoration: const InputDecoration(hintText: 'Paste the text here…', alignLabelWithHint: true),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: FlcSpace.xs),
                child: Text(_error!, style: TextStyle(color: FlcColors.errorAccent(context))),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _busy ? null : _run,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high_outlined),
          label: Text(_busy ? 'Reading…' : 'Sort it out'),
        ),
      ],
    );
  }
}
