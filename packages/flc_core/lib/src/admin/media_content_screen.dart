import 'package:intl/intl.dart';

import 'package:flutter/material.dart';

import '../events_admin/event_admin_repository.dart';
import '../events_admin/widgets/editor_widgets.dart';
import '../models/media_post.dart';
import '../theme/flc_colors.dart';
import '../theme/flc_spacing.dart';
import '../theme/flc_typography.dart';
import 'media_admin_repository.dart';
import 'media_manual_widgets.dart';

/// Replaces the old "Content" placeholder — feedback: "how do you edit the
/// media tab? Any way for an admin to do changes there? Maybe a manual way
/// to add podcast links and YT videos?" Shared by the admin console and
/// the app's staff area, same pattern as NotificationsScreen.
///
/// Podcasts: a "sync now" button only — that table is fully owned by the
/// RSS feed (see MediaAdminRepository's doc comment for why there's no
/// manual-add for it). Videos: a real list with manual add/delete, since
/// there's no YouTube API sync yet to hand that over to.
class MediaContentScreen extends StatefulWidget {
  const MediaContentScreen({required this.repository, this.embedded = false, super.key});

  final MediaAdminRepository repository;

  /// True inside the admin console's shell (no app bar of its own).
  final bool embedded;

  @override
  State<MediaContentScreen> createState() => _MediaContentScreenState();
}

class _MediaContentScreenState extends State<MediaContentScreen> {
  late Future<List<MediaPostModel>> _posts = widget.repository.listMediaPosts();
  bool _syncingPodcast = false;
  bool _syncingArticles = false;

  void _reload() => setState(() => _posts = widget.repository.listMediaPosts());

  Future<void> _syncPodcast() async {
    setState(() => _syncingPodcast = true);
    try {
      final int upserted = await widget.repository.triggerPodcastSync();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Podcast feed synced — $upserted episode(s) updated.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(EventAdminRepository.describeError(e))));
    } finally {
      if (mounted) setState(() => _syncingPodcast = false);
    }
  }

  Future<void> _syncArticles() async {
    setState(() => _syncingArticles = true);
    try {
      await widget.repository.triggerWordpressSync();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Article sync started.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(EventAdminRepository.describeError(e))));
    } finally {
      if (mounted) setState(() => _syncingArticles = false);
    }
  }

  Future<void> _addVideo() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _AddVideoDialog(repository: widget.repository),
    );
    if (added == true) _reload();
  }

  Future<void> _deleteVideo(MediaPostModel post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this video?'),
        content: Text('"${post.title}" will no longer show in the app.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteMediaPost(post.id);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(EventAdminRepository.describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final double gutter = widget.embedded ? FlcSpace.xl : FlcSpace.md;

    final Widget body = ListView(
      padding: EdgeInsets.all(gutter),
      children: <Widget>[
        if (widget.embedded) ...<Widget>[
          Text('Media', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: FlcSpace.md),
        ],
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionCard(
                  title: 'Podcast & articles',
                  subtitle: 'Both sync on their own every hour — use these to pull in a new episode or post right away instead of waiting.',
                  child: Wrap(
                    spacing: FlcSpace.sm,
                    runSpacing: FlcSpace.sm,
                    children: <Widget>[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: FlcColors.accent(context)),
                        onPressed: _syncingPodcast ? null : _syncPodcast,
                        icon: _syncingPodcast
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.podcasts_outlined, size: 18),
                        label: const Text('Sync podcast now'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: FlcColors.accent(context)),
                        onPressed: _syncingArticles ? null : _syncArticles,
                        icon: _syncingArticles
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.article_outlined, size: 18),
                        label: const Text('Sync articles now'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FlcSpace.md),
                Row(
                  children: <Widget>[
                    const Expanded(child: Text('Videos', style: FlcTextStyles.h3)),
                    FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: _addVideo, icon: const Icon(Icons.add, size: 18), label: const Text('Add video')),
                  ],
                ),
                const SizedBox(height: FlcSpace.xs),
                Text(
                  'No automatic YouTube sync yet — add each video\'s link here until that\'s set up.',
                  style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)),
                ),
                const SizedBox(height: FlcSpace.sm),
                FutureBuilder<List<MediaPostModel>>(
                  future: _posts,
                  builder: (BuildContext context, AsyncSnapshot<List<MediaPostModel>> snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(padding: EdgeInsets.all(FlcSpace.md), child: LinearProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Text("Couldn't load videos. ${EventAdminRepository.describeError(snap.error!)}", style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.errorAccent(context)));
                    }
                    final List<MediaPostModel> posts = snap.data ?? const <MediaPostModel>[];
                    if (posts.isEmpty) {
                      return Text('No videos added yet.', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)));
                    }
                    return Card(
                      child: Column(
                        children: <Widget>[
                          for (final MediaPostModel post in posts)
                            ListTile(
                              leading: post.thumbnailUrl == null
                                  ? const Icon(Icons.play_circle_outline)
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(post.thumbnailUrl!, width: 64, height: 36, fit: BoxFit.cover),
                                    ),
                              title: Text(post.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(DateFormat('d MMM yyyy').format(post.publishedAt.toLocal()) + (post.isLive ? ' · Live' : '')),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline, color: FlcColors.errorAccent(context)),
                                tooltip: 'Remove',
                                onPressed: () => _deleteVideo(post),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: FlcSpace.xl),
                ManualSection(
                  title: 'Podcast episodes',
                  hint: 'Episodes from the RSS feed appear on their own. Add one here only if it isn\'t in the feed — you\'ll need a direct link to the audio file.',
                  addLabel: 'Add episode',
                  emptyText: 'No hand-added episodes.',
                  load: widget.repository.listManualPodcasts,
                  remove: widget.repository.deletePodcastEpisode,
                  dialogBuilder: (BuildContext c) => AddPodcastDialog(repository: widget.repository),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Media')),
      body: body,
    );
  }
}

class _AddVideoDialog extends StatefulWidget {
  const _AddVideoDialog({required this.repository});

  final MediaAdminRepository repository;

  @override
  State<_AddVideoDialog> createState() => _AddVideoDialogState();
}

class _AddVideoDialogState extends State<_AddVideoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _linkController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime _publishedAt = DateTime.now();
  bool _isLive = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _linkController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.addYoutubeVideo(
        youtubeIdOrUrl: _linkController.text,
        title: _titleController.text,
        description: _descriptionController.text,
        publishedAt: _publishedAt,
        isLive: _isLive,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = EventAdminRepository.describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a video'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                controller: _linkController,
                decoration: const InputDecoration(labelText: 'YouTube link or video ID', hintText: 'youtube.com/watch?v=…'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: FlcSpace.sm),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: FlcSpace.sm),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: FlcSpace.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('Published ${DateFormat('d MMM yyyy').format(_publishedAt)}', style: FlcTextStyles.bodySmall),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _publishedAt,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (picked != null) setState(() => _publishedAt = picked);
                    },
                    child: const Text('Change'),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Currently live'),
                value: _isLive,
                onChanged: (v) => setState(() => _isLive = v),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: FlcSpace.xs),
                Text(_error!, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.errorAccent(context))),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add'),
        ),
      ],
    );
  }
}
