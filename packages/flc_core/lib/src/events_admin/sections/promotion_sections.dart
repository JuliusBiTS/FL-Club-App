import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../../theme/flc_colors.dart';
import '../../theme/flc_spacing.dart';
import '../../theme/flc_typography.dart';
import '../../util/london_time.dart';
import '../../widgets/staff_pick_bubble.dart';
import '../event_draft.dart';
import '../event_editor_controller.dart';
import '../widgets/editor_widgets.dart';
import 'push_composer.dart';

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
          const Divider(height: FlcSpace.xl),
          Text('A staff member\'s pick', style: FlcTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            'Optional, and independent of the ribbon above — a personal note from someone on the team about why this one\'s worth going to.',
            style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate),
          ),
          const SizedBox(height: FlcSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 72,
                child: ImageSlot(
                  repository: controller.repository,
                  url: d.pickByPhotoUrl,
                  aspectRatio: 1,
                  label: 'Photo',
                  enabled: enabled,
                  onChanged: (String? url) {
                    d.pickByPhotoUrl = url;
                    controller.touch();
                  },
                ),
              ),
              const SizedBox(width: FlcSpace.sm),
              Expanded(
                child: Column(
                  children: <Widget>[
                    TextFormField(
                      initialValue: d.pickByName,
                      enabled: enabled,
                      decoration: const InputDecoration(labelText: 'Their name', isDense: true),
                      onChanged: (String v) {
                        d.pickByName = v;
                        controller.touch();
                      },
                    ),
                    const SizedBox(height: FlcSpace.xs),
                    TextFormField(
                      initialValue: d.pickQuote,
                      enabled: enabled,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 280,
                      decoration: const InputDecoration(
                        labelText: 'Their quote',
                        hintText: 'e.g. "One of my favourite panels this year."',
                        alignLabelWithHint: true,
                      ),
                      onChanged: (String v) {
                        d.pickQuote = v;
                        controller.touch();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (d.pickQuote.trim().isNotEmpty && d.pickByName.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: FlcSpace.sm),
            Text('How it will look', style: FlcTextStyles.caption.copyWith(color: FlcColors.slate)),
            const SizedBox(height: FlcSpace.xxs),
            StaffPickBubble(name: d.pickByName.trim(), quote: d.pickQuote, photoUrl: d.pickByPhotoUrl),
          ],
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
          PushComposer(
            repository: widget.controller.repository,
            draft: widget.controller.draft,
            eventIsLive: widget.controller.isLive,
            onSent: () => setState(() => _history = _load()),
          ),
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
                  for (final Map<String, dynamic> r in rows) CampaignTile(row: r),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One row of push history.
class CampaignTile extends StatelessWidget {
  const CampaignTile({required this.row, super.key});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final DateTime? t = row['created_at'] is String ? DateTime.tryParse(row['created_at'] as String) : null;
    final String when = t == null ? '' : LondonTime.format(t, pattern: 'd MMM, HH:mm');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.notifications_active_outlined, size: 20),
      title: Text(row['title'] as String? ?? ''),
      subtitle: Text('${pushAudienceLabels[row['audience']] ?? row['audience']} · ${row['delivered']}/${row['recipients']} delivered · $when'),
    );
  }
}
