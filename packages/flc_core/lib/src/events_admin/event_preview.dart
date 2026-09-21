import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import '../theme/flc_colors.dart';
import '../theme/flc_spacing.dart';
import '../theme/flc_typography.dart';
import '../widgets/event_badges.dart';
import '../widgets/event_hero_fallback.dart';
import 'event_draft.dart';

/// The event as it will appear on a card in the app's Events tab — same
/// layout and the same [EventBadges], updated as the person types.
class EventPreviewCard extends StatelessWidget {
  const EventPreviewCard({required this.draft, super.key});

  final EventDraft draft;

  @override
  Widget build(BuildContext context) {
    final String when = draft.startsAt == null ? 'Date to be set' : DateFormat('EEE d MMM, HH:mm').format(draft.startsAt!);
    final String where = draft.venueRoom.trim().isNotEmpty ? draft.venueRoom.trim() : draft.venueName;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 16 / 9,
            child: draft.heroImageUrl == null
                ? EventHeroFallback(category: draft.category)
                : Image.network(
                    draft.heroImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (BuildContext c, Object e, StackTrace? s) => const ColoredBox(color: FlcColors.line),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(FlcSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (draft.category != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FlcSpace.xxs),
                    child: Text(draft.category!.toUpperCase(), style: FlcTextStyles.overline.copyWith(color: FlcColors.brand)),
                  ),
                Text(
                  draft.title.trim().isEmpty ? 'Your event title' : draft.title.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FlcTextStyles.h3.copyWith(color: draft.title.trim().isEmpty ? FlcColors.slate : null),
                ),
                const SizedBox(height: FlcSpace.xxs),
                Text('$when · $where', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate)),
                if (draft.summary.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: FlcSpace.xs),
                  Text(draft.summary.trim(), maxLines: 3, overflow: TextOverflow.ellipsis, style: FlcTextStyles.bodySmall),
                ],
                if (draft.highlight != EventHighlight.none || draft.perks.isNotEmpty || draft.membersOnly) ...<Widget>[
                  const SizedBox(height: FlcSpace.sm),
                  Wrap(
                    spacing: FlcSpace.xs,
                    runSpacing: FlcSpace.xs,
                    children: <Widget>[
                      EventBadges(highlight: draft.highlight, perks: draft.perks, dense: true),
                      if (draft.membersOnly)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: FlcSpace.xs, vertical: 3),
                          decoration: BoxDecoration(
                            color: FlcColors.brand.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(FlcRadius.input),
                          ),
                          child: Text('Members only', style: FlcTextStyles.caption.copyWith(color: FlcColors.brand, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Draft / Scheduled / Live / Postponed / Cancelled / Archived.
class EventStatusChip extends StatelessWidget {
  const EventStatusChip({required this.status, this.scheduled = false, this.onDark = false, super.key});

  final String status;

  /// A draft that has a publish time set.
  final bool scheduled;

  /// On the brand-coloured app bar, where the usual tints would disappear.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (status) {
      'published' => ('Live', FlcColors.success),
      'postponed' => ('Postponed', FlcColors.warning),
      'cancelled' => ('Cancelled', FlcColors.error),
      'archived' => ('Archived', FlcColors.slate),
      _ => scheduled ? ('Scheduled', FlcColors.brand) : ('Draft', FlcColors.slate),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FlcSpace.xs, vertical: 2),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.18) : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(FlcRadius.input),
      ),
      child: Text(
        label,
        style: FlcTextStyles.caption.copyWith(color: onDark ? Colors.white : color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// "Before you publish" — the live list of problems and things worth a look.
class EditorChecklist extends StatelessWidget {
  const EditorChecklist({required this.draft, super.key});

  final EventDraft draft;

  @override
  Widget build(BuildContext context) {
    final EventIssues issues = draft.validate(publishing: true);

    if (issues.errors.isEmpty && issues.warnings.isEmpty) {
      return const _ChecklistRow(icon: Icons.check_circle_outline, color: FlcColors.success, text: 'Everything looks ready to publish.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final String e in issues.errors) _ChecklistRow(icon: Icons.error_outline, color: FlcColors.error, text: e),
        for (final String w in issues.warnings) _ChecklistRow(icon: Icons.info_outline, color: FlcColors.warning, text: w),
      ],
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FlcSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: FlcSpace.xs),
          Expanded(child: Text(text, style: FlcTextStyles.bodySmall)),
        ],
      ),
    );
  }
}
