import 'package:cached_network_image/cached_network_image.dart';
import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Briefing §9.1. Full member-price surfacing (struck-through standard
/// price, live ticket-type-aware pricing) needs the event's ticket types,
/// which the feed doesn't fetch per-card for cost/latency reasons — that
/// richer version lands with checkout in M3. For now this shows the date,
/// venue and a plain status chip, which is enough to make M1's "browse
/// real events on a phone" demo land.
class EventCard extends StatelessWidget {
  const EventCard({required this.event, required this.onTap, super.key});

  final EventModel event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE d MMM, HH:mm'); // briefing §6: "Thu 3 Sep 2026" style, 24h/12h per device locale — TODO: respect device locale format instead of hard-coding EEE d MMM, HH:mm once l10n is wired up (§6)
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.xs),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 16 / 9,
              child: event.heroImagePath == null
                  ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
                  : CachedNetworkImage(imageUrl: event.heroImagePath!, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.all(FlcSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (event.category != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: FlcSpace.xxs),
                      child: Text(event.category!.toUpperCase(), style: FlcTextStyles.overline.copyWith(color: FlcColors.red)),
                    ),
                  Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: FlcTextStyles.h3),
                  const SizedBox(height: FlcSpace.xxs),
                  Text(
                    '${dateFormat.format(event.startsAt.toLocal())} · ${event.venueRoom ?? event.venueName}',
                    style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate),
                  ),
                  if (event.membersOnly) ...<Widget>[
                    const SizedBox(height: FlcSpace.xs),
                    const _Chip(label: 'Members only'),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FlcSpace.xs, vertical: 2),
      decoration: BoxDecoration(
        color: FlcColors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(FlcRadius.input),
      ),
      child: Text(label, style: FlcTextStyles.caption.copyWith(color: FlcColors.red, fontWeight: FontWeight.w600)),
    );
  }
}
