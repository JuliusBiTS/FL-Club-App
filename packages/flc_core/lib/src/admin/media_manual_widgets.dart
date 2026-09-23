import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../events_admin/event_admin_repository.dart';
import '../theme/flc_colors.dart';
import '../theme/flc_spacing.dart';
import '../theme/flc_typography.dart';
import 'media_admin_repository.dart';

/// A list of hand-added items (podcast episodes / articles) with add + remove.
class ManualSection extends StatefulWidget {
  const ManualSection({
    required this.title,
    required this.hint,
    required this.addLabel,
    required this.emptyText,
    required this.load,
    required this.remove,
    required this.dialogBuilder,
    super.key,
  });

  final String title;
  final String hint;
  final String addLabel;
  final String emptyText;
  final Future<List<ManualItem>> Function() load;
  final Future<void> Function(String id) remove;
  final WidgetBuilder dialogBuilder;

  @override
  State<ManualSection> createState() => _ManualSectionState();
}

class _ManualSectionState extends State<ManualSection> {
  late Future<List<ManualItem>> _items = widget.load();

  void _reload() => setState(() => _items = widget.load());

  Future<void> _add() async {
    final bool? added = await showDialog<bool>(context: context, builder: widget.dialogBuilder);
    if (added == true) _reload();
  }

  Future<void> _remove(ManualItem item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Remove this?'),
        content: Text('"${item.title}" will no longer show in the app.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.remove(item.id);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(EventAdminRepository.describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(widget.title, style: FlcTextStyles.h3)),
            FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: _add, icon: const Icon(Icons.add, size: 18), label: Text(widget.addLabel)),
          ],
        ),
        const SizedBox(height: FlcSpace.xs),
        Text(widget.hint, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context))),
        const SizedBox(height: FlcSpace.sm),
        FutureBuilder<List<ManualItem>>(
          future: _items,
          builder: (BuildContext context, AsyncSnapshot<List<ManualItem>> snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(FlcSpace.md), child: LinearProgressIndicator());
            }
            if (snap.hasError) {
              return Text(
                "Couldn't load. ${EventAdminRepository.describeError(snap.error!)}",
                style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.errorAccent(context)),
              );
            }
            final List<ManualItem> items = snap.data ?? const <ManualItem>[];
            if (items.isEmpty) {
              return Text(widget.emptyText, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)));
            }
            return Card(
              child: Column(
                children: <Widget>[
                  for (final ManualItem item in items)
                    ListTile(
                      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(DateFormat('d MMM yyyy').format(item.publishedAt.toLocal())),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline, color: FlcColors.errorAccent(context)),
                        tooltip: 'Remove',
                        onPressed: () => _remove(item),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Shared shell for the two add dialogs: form, date, save/cancel, error line.
class _AddDialogBase extends StatefulWidget {
  const _AddDialogBase({required this.title, required this.fields, required this.onSave, required this.formKey});

  final String title;
  final List<Widget> Function(DateTime published, VoidCallback pickDate) fields;
  final Future<void> Function(DateTime published) onSave;
  final GlobalKey<FormState> formKey;

  @override
  State<_AddDialogBase> createState() => _AddDialogBaseState();
}

class _AddDialogBaseState extends State<_AddDialogBase> {
  DateTime _published = DateTime.now();
  bool _saving = false;
  String? _error;

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _published,
      firstDate: DateTime(2010),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _published = picked);
  }

  Future<void> _save() async {
    if (!(widget.formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_published);
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: widget.formKey,
        child: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ...widget.fields(_published, _pickDate),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: FlcSpace.xs),
                  Text(_error!, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.errorAccent(context))),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Add'),
        ),
      ],
    );
  }
}

String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

Widget _dateRow(DateTime published, VoidCallback pick) => Row(
      children: <Widget>[
        Expanded(child: Text('Published ${DateFormat('d MMM yyyy').format(published)}', style: FlcTextStyles.bodySmall)),
        TextButton(onPressed: pick, child: const Text('Change')),
      ],
    );

class AddPodcastDialog extends StatefulWidget {
  const AddPodcastDialog({required this.repository, super.key});

  final MediaAdminRepository repository;

  @override
  State<AddPodcastDialog> createState() => _AddPodcastDialogState();
}

class _AddPodcastDialogState extends State<AddPodcastDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _audio = TextEditingController();
  final _description = TextEditingController();
  final _image = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _audio.dispose();
    _description.dispose();
    _image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AddDialogBase(
      title: 'Add a podcast episode',
      formKey: _formKey,
      onSave: (DateTime published) => widget.repository.addPodcastEpisode(
        title: _title.text,
        audioUrl: _audio.text,
        description: _description.text,
        imageUrl: _image.text,
        publishedAt: published,
      ),
      fields: (DateTime published, VoidCallback pick) => <Widget>[
        TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Title'), validator: _required),
        const SizedBox(height: FlcSpace.sm),
        TextFormField(
          controller: _audio,
          decoration: const InputDecoration(labelText: 'Audio link (.mp3 etc.)', hintText: 'https://…'),
          validator: _required,
        ),
        const SizedBox(height: FlcSpace.sm),
        TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Description (optional)'), minLines: 2, maxLines: 4),
        const SizedBox(height: FlcSpace.sm),
        TextFormField(controller: _image, decoration: const InputDecoration(labelText: 'Cover image link (optional)')),
        const SizedBox(height: FlcSpace.sm),
        _dateRow(published, pick),
      ],
    );
  }
}

