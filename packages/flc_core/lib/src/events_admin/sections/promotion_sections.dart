import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../../theme/flc_colors.dart';
import '../../theme/flc_spacing.dart';
import '../../theme/flc_typography.dart';
import '../../util/london_time.dart';
import '../../widgets/event_badges.dart';
import '../event_admin_repository.dart';
import '../event_draft.dart';
import '../event_editor_controller.dart';
import '../widgets/editor_widgets.dart';

const List<String> _perkSuggestions = <String>[
  'Free drink with your ticket',
  'Free welcome drink',
  'Meet the speaker',
  'Signed copies available',
];

/// Highlight ribbon, perks and scheduled publishing.
class PromotionSection extends StatelessWidget {
  const PromotionSection({required this.controller, super.key});

  final EventEditorController controller;

  @override
  Widget build(BuildContext context) {
    final EventDraft d = controller.draft;
    final bool enabled = !controller.readOnly;

    String hint(EventHighlight h) => switch (h) {
          EventHighlight.none => 'No ribbon.',
          EventHighlight.fcRecommends => 'The club\'s own pick — pinned to the top of the app\'s Events tab.',
          EventHighlight.staffPick => 'A softer recommendation from the team.',
          EventHighlight.specialOffer => 'A deal is on — pair it with a perk below.',
        };

    return SectionCard(
      title: 'Promotion',
      subtitle: 'Make an event stand out in the app.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: FlcSpace.xs,
            runSpacing: FlcSpace.xs,
            children: <Widget>[
              for (final EventHighlight h in EventHighlight.values)
                ChoiceChip(
                  label: Text(h.badgeLabel ?? 'No highlight'),
                  selected: d.highlight == h,
                  onSelected: enabled
                      ? (bool _) {
                          d.highlight = h;
                          controller.touch();
                        }
                      : null,
                ),
            ],
          ),
          const SizedBox(height: FlcSpace.xs),
          Text(hint(d.highlight), style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate)),
          const SizedBox(height: FlcSpace.md),
          ChipsInput(
            label: 'Perks',
            hint: 'e.g. Free drink with your ticket',
            values: d.perks,
            enabled: enabled,
            maxItems: kMaxPerks,
            maxLength: kMaxPerkLength,
            suggestions: _perkSuggestions,
            onChanged: (List<String> v) {
              d.perks = v;
              controller.touch();
            },
          ),
          const SizedBox(height: FlcSpace.sm),
          Row(
            children: <Widget>[
              const Icon(Icons.local_fire_department_outlined, size: 18, color: FlcColors.slate),
              const SizedBox(width: FlcSpace.xs),
              Expanded(
                child: Text(
                  '"Selling fast" appears on its own once 75% of seats are sold — nothing to switch on.',
                  style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate),
                ),
              ),
            ],
          ),
          if (!controller.isLive) ...<Widget>[
            const Divider(height: FlcSpace.xl),
            DateTimeField(
              label: 'Publish automatically at',
              value: d.publishAt,
              enabled: enabled,
              clearable: true,
              helper: 'Optional. Set a time, then choose "Schedule" — the event goes live by itself. Leave empty to publish by hand.',
              onChanged: (DateTime? v) {
                d.publishAt = v;
                controller.touch();
              },
            ),
          ],
        ],
      ),
    );
  }
}

const Map<String, String> _kindLabels = <String, String>{
  'new_event': 'New event announcement',
  'recommendation': 'FC Recommends / offer',
  'announcement': 'General announcement',
  'event_update': 'Update for ticket holders',
};

const Map<String, String> _audienceLabels = <String, String>{
  'all': 'Everyone who has notifications on',
  'members': 'Members only',
  'ticket_holders': 'People holding a ticket',
};

/// Composes and sends a push notification about one event. Usable inline
/// (the Notifications section) or inside a dialog (right after publishing).
class PushComposer extends StatefulWidget {
  const PushComposer({
    required this.controller,
    this.initialKind = 'new_event',
    this.initialTitle,
    this.initialBody,
    this.onSent,
    super.key,
  });

  final EventEditorController controller;
  final String initialKind;
  final String? initialTitle;
  final String? initialBody;
  final VoidCallback? onSent;

  @override
  State<PushComposer> createState() => _PushComposerState();
}

class _PushComposerState extends State<PushComposer> {
  late String _kind = widget.initialKind;
  late String _audience = widget.initialKind == 'event_update' ? 'ticket_holders' : 'all';
  late final TextEditingController _title = TextEditingController(text: widget.initialTitle ?? _suggestTitle(_kind));
  late final TextEditingController _body = TextEditingController(text: widget.initialBody ?? _suggestBody());

  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  EventDraft get _d => widget.controller.draft;

  String _suggestTitle(String kind) {
    final String t = _d.title.trim().isEmpty ? 'an upcoming event' : _d.title.trim();
    final String s = switch (kind) {
      'new_event' => 'New at the Frontline Club: $t',
      'recommendation' => 'FC Recommends: $t',
      'event_update' => 'Update: $t',
      _ => t,
    };
    return s.length > 65 ? '${s.substring(0, 62)}…' : s;
  }

  String _suggestBody() {
    final String when = _d.startsAt == null ? '' : DateFormatShort.format(_d.startsAt!);
    final String base = _d.summary.trim().isNotEmpty ? _d.summary.trim() : (_d.subtitle.trim().isNotEmpty ? _d.subtitle.trim() : '');
    final String s = <String>[if (when.isNotEmpty) when, if (base.isNotEmpty) base].join(' · ');
    return s.length > 240 ? '${s.substring(0, 237)}…' : s;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _run({required bool preview}) async {
    final EventEditorController c = widget.controller;
    setState(() {
      _busy = true;
      _message = null;
    });

    if (!preview) {
      final String label = _audienceLabels[_audience]!.toLowerCase();
      final bool? go = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Send this notification?'),
          content: Text('"${_title.text.trim()}"\n\nIt goes to: $label.\nThis can\'t be recalled once sent.'),
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
      final PushResult r = await c.repository.sendPush(
        kind: _kind,
        audience: _audience,
        title: _title.text.trim(),
        body: _body.text.trim(),
        eventId: c.draft.id,
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
    final EventDraft d = _d;
    final bool needsLive = (_kind == 'new_event' || _kind == 'recommendation') && !widget.controller.isLive;
    final bool canSend = !_busy && !needsLive && _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;
    final List<String> audiences = _kind == 'event_update' ? <String>['ticket_holders'] : _audienceLabels.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ResponsiveRow(
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: _kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'What kind of message'),
              items: <DropdownMenuItem<String>>[
                for (final MapEntry<String, String> e in _kindLabels.entries) DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
              ],
              onChanged: (String? v) => setState(() {
                _kind = v ?? 'new_event';
                if (_kind == 'event_update') _audience = 'ticket_holders';
                if (_kind != 'event_update' && _audience == 'ticket_holders') _audience = 'all';
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
                for (final String a in audiences) DropdownMenuItem<String>(value: a, child: Text(_audienceLabels[a]!)),
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
          Padding(
            padding: const EdgeInsets.only(bottom: FlcSpace.xs),
            child: Text(
              'Publish the event first — people can\'t open an event that isn\'t live yet.',
              style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.warning),
            ),
          ),
        if (d.isNew)
          Padding(
            padding: const EdgeInsets.only(bottom: FlcSpace.xs),
            child: Text('Save the event first to send a notification about it.', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.warning)),
          ),
        Wrap(
          spacing: FlcSpace.xs,
          runSpacing: FlcSpace.xs,
          children: <Widget>[
            OutlinedButton.icon(
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Check who\'ll get it'),
              onPressed: _busy || d.isNew ? null : () => _run(preview: true),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_outlined),
              label: const Text('Send notification'),
              onPressed: canSend && !d.isNew ? () => _run(preview: false) : null,
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
}

/// Tiny date helper kept next to its only user.
abstract final class DateFormatShort {
  static String format(DateTime londonWallClock) {
    final DateTime utc = LondonTime.toUtc(londonWallClock);
    return LondonTime.format(utc, pattern: 'EEE d MMM, HH:mm');
  }
}

/// The inline "tell people about it" block, with what has already been sent.
class NotificationsSection extends StatefulWidget {
  const NotificationsSection({required this.controller, super.key});

  final EventEditorController controller;

  @override
  State<NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<NotificationsSection> {
  late Future<List<Map<String, dynamic>>> _history = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final String? id = widget.controller.draft.id;
    if (id == null) return <Map<String, dynamic>>[];
    try {
      return await widget.controller.repository.pushCampaigns(eventId: id);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Notifications',
      subtitle: 'Send a push notification about this event to people\'s phones.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PushComposer(controller: widget.controller, onSent: () => setState(() => _history = _load())),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _history,
            builder: (BuildContext context, AsyncSnapshot<List<Map<String, dynamic>>> snap) {
              final List<Map<String, dynamic>> rows = snap.data ?? const <Map<String, dynamic>>[];
              if (rows.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Divider(height: FlcSpace.xl),
                  Text('Already sent for this event', style: FlcTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: FlcSpace.xs),
                  for (final Map<String, dynamic> r in rows)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.notifications_active_outlined, size: 20),
                      title: Text(r['title'] as String? ?? ''),
                      subtitle: Text(
                        '${_audienceLabels[r['audience']] ?? r['audience']} · ${r['delivered']}/${r['recipients']} delivered · ${_when(r['created_at'])}',
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _when(Object? iso) {
    final DateTime? t = iso is String ? DateTime.tryParse(iso) : null;
    return t == null ? '' : LondonTime.format(t, pattern: 'd MMM, HH:mm');
  }
}

/// A live look at how the event will appear as a card in the app.
class PromotionPreviewBadges extends StatelessWidget {
  const PromotionPreviewBadges({required this.draft, super.key});

  final EventDraft draft;

  @override
  Widget build(BuildContext context) => EventBadges(highlight: draft.highlight, perks: draft.perks, dense: true);
}
