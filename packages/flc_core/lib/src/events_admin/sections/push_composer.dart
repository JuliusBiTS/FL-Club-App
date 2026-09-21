import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/flc_colors.dart';
import '../../theme/flc_spacing.dart';
import '../../theme/flc_typography.dart';
import '../event_admin_repository.dart';
import '../event_draft.dart';
import '../widgets/editor_widgets.dart';

const Map<String, String> pushKindLabels = <String, String>{
  'new_event': 'New event announcement',
  'recommendation': 'FC Recommends / offer',
  'announcement': 'General announcement',
  'event_update': 'Update for ticket holders',
};

const Map<String, String> pushAudienceLabels = <String, String>{
  'all': 'Everyone who has notifications on',
  'members': 'Members only',
  'ticket_holders': 'People holding a ticket',
};

/// "Wed 9 Sep, 19:00" from a London wall-clock value.
String shortWhen(DateTime londonWallClock) => DateFormat('EEE d MMM, HH:mm').format(londonWallClock);

/// Composes and sends a push notification. With a [draft] it is about that
/// event (and can target its ticket holders); without one it is a general
/// club announcement. Usable inline or inside a dialog.
///
/// "Check who'll get it" counts the audience without sending; "Send" always
/// asks for confirmation first, because a sent notification can't be recalled.
class PushComposer extends StatefulWidget {
  const PushComposer({
    required this.repository,
    this.draft,
    this.eventIsLive = false,
    this.initialKind,
    this.initialTitle,
    this.initialBody,
    this.onSent,
    super.key,
  });

  final EventAdminRepository repository;

  /// The event this is about, or null for a general announcement.
  final EventDraft? draft;
  final bool eventIsLive;
  final String? initialKind;
  final String? initialTitle;
  final String? initialBody;
  final VoidCallback? onSent;

  @override
  State<PushComposer> createState() => _PushComposerState();
}

class _PushComposerState extends State<PushComposer> {
  bool get _forEvent => widget.draft != null;

  late String _kind = widget.initialKind ?? (_forEvent ? 'new_event' : 'announcement');
  late String _audience = _kind == 'event_update' ? 'ticket_holders' : 'all';
  late final TextEditingController _title = TextEditingController(text: widget.initialTitle ?? _suggestTitle(_kind));
  late final TextEditingController _body = TextEditingController(text: widget.initialBody ?? _suggestBody());

  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  static String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

  String _suggestTitle(String kind) {
    final EventDraft? d = widget.draft;
    if (d == null) return '';
    final String t = d.title.trim().isEmpty ? 'an upcoming event' : d.title.trim();
    return _clip(
      switch (kind) {
        'new_event' => 'New at the Frontline Club: $t',
        'recommendation' => 'FC Recommends: $t',
        'event_update' => 'Update: $t',
        _ => t,
      },
      65,
    );
  }

  String _suggestBody() {
    final EventDraft? d = widget.draft;
    if (d == null) return '';
    final String base = d.summary.trim().isNotEmpty ? d.summary.trim() : d.subtitle.trim();
    return _clip(<String>[if (d.startsAt != null) shortWhen(d.startsAt!), if (base.isNotEmpty) base].join(' · '), 240);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  List<String> get _audiences {
    if (_kind == 'event_update') return <String>['ticket_holders'];
    return _forEvent ? <String>['all', 'members', 'ticket_holders'] : <String>['all', 'members'];
  }

  Future<void> _run({required bool preview}) async {
    setState(() {
      _busy = true;
      _message = null;
    });

    if (!preview) {
      final bool? go = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Send this notification?'),
          content: Text('"${_title.text.trim()}"\n\nIt goes to: ${pushAudienceLabels[_audience]!.toLowerCase()}.\nThis can\'t be recalled once sent.'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send now')),
          ],
        ),
      );
      if (go != true) {
        if (mounted) setState(() => _busy = false);
        return;
      }
    }

    try {
      final PushResult r = await widget.repository.sendPush(
        kind: _kind,
        audience: _audience,
        title: _title.text.trim(),
        body: _body.text.trim(),
        eventId: widget.draft?.id,
        preview: preview,
      );
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = preview
            ? (r.recipients == 0
                ? 'Nobody would receive this yet — nobody in that group has notifications switched on.'
                : 'This would reach ${r.recipients} device${r.recipients == 1 ? '' : 's'}.')
            : 'Sent to ${r.delivered} of ${r.recipients} device${r.recipients == 1 ? '' : 's'}${r.failed > 0 ? ' (${r.failed} failed)' : ''}.';
      });
      if (!preview) widget.onSent?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = EventAdminRepository.describeError(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final EventDraft? d = widget.draft;
    final bool needsLive = _forEvent && (_kind == 'new_event' || _kind == 'recommendation') && !widget.eventIsLive;
    final bool unsavedEvent = d != null && d.isNew;
    final bool filled = _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;
    final List<String> audiences = _audiences;
    final Iterable<String> kinds = _forEvent ? pushKindLabels.keys : const <String>['announcement'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ResponsiveRow(
          children: <Widget>[
            if (_forEvent)
              DropdownButtonFormField<String>(
                initialValue: _kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'What kind of message'),
                items: <DropdownMenuItem<String>>[
                  for (final String k in kinds) DropdownMenuItem<String>(value: k, child: Text(pushKindLabels[k]!)),
                ],
                onChanged: (String? v) => setState(() {
                  _kind = v ?? 'new_event';
                  _audience = _kind == 'event_update' ? 'ticket_holders' : (_audience == 'ticket_holders' ? 'all' : _audience);
                  _title.text = _suggestTitle(_kind);
                  _message = null;
                }),
              ),
            DropdownButtonFormField<String>(
              key: ValueKey<String>('aud-$_kind'),
              initialValue: audiences.contains(_audience) ? _audience : audiences.first,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Who gets it'),
              items: <DropdownMenuItem<String>>[
                for (final String a in audiences) DropdownMenuItem<String>(value: a, child: Text(pushAudienceLabels[a]!)),
              ],
              onChanged: (String? v) => setState(() {
                _audience = v ?? 'all';
                _message = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: FlcSpace.sm),
        TextField(
          controller: _title,
          maxLength: 65,
          decoration: const InputDecoration(labelText: 'Headline'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: FlcSpace.xs),
        TextField(
          controller: _body,
          maxLength: 240,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Message'),
          onChanged: (_) => setState(() {}),
        ),
        if (needsLive)
          _hint('Publish the event first — people can\'t open an event that isn\'t live yet.'),
        if (unsavedEvent) _hint('Save the event first to send a notification about it.'),
        Wrap(
          spacing: FlcSpace.xs,
          runSpacing: FlcSpace.xs,
          children: <Widget>[
            OutlinedButton.icon(
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Check who\'ll get it'),
              onPressed: _busy || unsavedEvent ? null : () => _run(preview: true),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_outlined),
              label: const Text('Send notification'),
              onPressed: !_busy && !needsLive && !unsavedEvent && filled ? () => _run(preview: false) : null,
            ),
          ],
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: FlcSpace.sm),
            child: Text(_message!, style: FlcTextStyles.bodySmall.copyWith(color: _messageIsError ? FlcColors.error : FlcColors.success)),
          ),
      ],
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(bottom: FlcSpace.xs),
        child: Text(text, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.warning)),
      );
}
