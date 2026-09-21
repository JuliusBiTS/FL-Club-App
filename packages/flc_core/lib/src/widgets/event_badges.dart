import 'package:flutter/material.dart';

import '../models/event.dart';
import '../theme/flc_colors.dart';
import '../theme/flc_spacing.dart';
import '../theme/flc_typography.dart';

/// The promotional ribbons on an event: FC Recommends / Staff pick / Special
/// offer (chosen by staff), "Selling fast" (derived from sales), and any
/// perks such as "Free drink with your ticket". One widget so the app's feed,
/// the event page and the editor's live preview always look identical.
class EventBadges extends StatelessWidget {
  const EventBadges({
    required this.highlight,
    this.perks = const <String>[],
    this.sellingFast = false,
    this.dense = false,
    super.key,
  });

  final EventHighlight highlight;
  final List<String> perks;
  final bool sellingFast;

  /// Smaller chips for cards; normal size for the detail page.
  final bool dense;

  bool get isEmpty => highlight == EventHighlight.none && perks.isEmpty && !sellingFast;

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: FlcSpace.xs,
      runSpacing: FlcSpace.xs,
      children: <Widget>[
        if (highlight != EventHighlight.none) _highlightChip(),
        if (sellingFast)
          _BadgeChip(
            label: 'Selling fast',
            icon: Icons.local_fire_department_outlined,
            background: FlcColors.error.withValues(alpha: 0.10),
            foreground: FlcColors.error,
            dense: dense,
          ),
        for (final String perk in perks)
          _BadgeChip(
            label: perk,
            icon: Icons.card_giftcard_outlined,
            background: Colors.transparent,
            foreground: FlcColors.graphite,
            outlined: true,
            dense: dense,
          ),
      ],
    );
  }

  Widget _highlightChip() {
    switch (highlight) {
      case EventHighlight.fcRecommends:
        return _BadgeChip(
          label: 'FC Recommends',
          icon: Icons.verified_outlined,
          background: FlcColors.brand,
          foreground: Colors.white,
          dense: dense,
        );
      case EventHighlight.staffPick:
        return _BadgeChip(
          label: 'Staff pick',
          icon: Icons.star_outline,
          background: FlcColors.brand.withValues(alpha: 0.10),
          foreground: FlcColors.brand,
          dense: dense,
        );
      case EventHighlight.specialOffer:
        return _BadgeChip(
          label: 'Special offer',
          icon: Icons.local_offer_outlined,
          background: FlcColors.warning.withValues(alpha: 0.14),
          foreground: const Color(0xFF7A5900), // warning tone, darkened to keep AA contrast on the tint
          dense: dense,
        );
      case EventHighlight.none:
        return const SizedBox.shrink();
    }
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.dense,
    this.outlined = false,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final bool dense;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? FlcSpace.xs : FlcSpace.sm, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(FlcRadius.input),
        border: outlined ? Border.all(color: FlcColors.line) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: dense ? 13 : 16, color: foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (dense ? FlcTextStyles.caption : FlcTextStyles.bodySmall).copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
