import 'package:flutter/material.dart';

import '../models/event.dart';
import '../theme/flc_colors.dart';
import '../theme/flc_spacing.dart';
import '../theme/flc_typography.dart';

/// The promotional ribbons on an event: FC Highlights / Staff pick / Special
/// offer (chosen by staff), "Selling fast" / "Sold out" (both derived from
/// sales, never both at once), and any perks such as "Free drink with your
/// ticket". One widget so the app's feed, the event page and the editor's
/// live preview always look identical.
class EventBadges extends StatelessWidget {
  const EventBadges({
    required this.highlight,
    this.perks = const <String>[],
    this.sellingFast = false,
    this.soldOut = false,
    this.dense = false,
    super.key,
  });

  final EventHighlight highlight;
  final List<String> perks;
  final bool sellingFast;
  final bool soldOut;

  /// Smaller chips for cards; normal size for the detail page.
  final bool dense;

  bool get isEmpty => highlight == EventHighlight.none && perks.isEmpty && !sellingFast && !soldOut;

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: FlcSpace.xs,
      runSpacing: FlcSpace.xs,
      children: <Widget>[
        if (highlight != EventHighlight.none) _highlightChip(context),
        // Solid, not tinted like the others — sold out is the one ribbon
        // that changes whether someone can act at all, so it gets more
        // visual weight, not less.
        if (soldOut)
          _BadgeChip(
            label: 'Sold out',
            icon: Icons.event_busy_outlined,
            background: FlcColors.errorAccent(context),
            foreground: Colors.white,
            dense: dense,
          )
        else if (sellingFast)
          _BadgeChip(
            label: 'Selling fast',
            icon: Icons.local_fire_department_outlined,
            background: FlcColors.error.withValues(alpha: 0.10),
            foreground: FlcColors.errorAccent(context),
            dense: dense,
          ),
        for (final String perk in perks)
          _BadgeChip(
            label: perk,
            icon: Icons.card_giftcard_outlined,
            background: Colors.transparent,
            // Confirmed near-invisible in a screenshot: plain graphite is
            // ~1.7:1 on the dark surface.
            foreground: FlcColors.secondaryStrong(context),
            outlined: true,
            dense: dense,
          ),
      ],
    );
  }

  Widget _highlightChip(BuildContext context) {
    // Label text comes from EventHighlight.badgeLabel — the single source of
    // truth also used by the editor's picker — so there's only ever one
    // place to rename a ribbon, not two copies that can drift apart.
    switch (highlight) {
      case EventHighlight.fcRecommends:
        return _BadgeChip(
          label: highlight.badgeLabel!,
          icon: Icons.verified_outlined,
          background: FlcColors.brand,
          foreground: Colors.white,
          dense: dense,
        );
      case EventHighlight.staffPick:
        return _BadgeChip(
          label: highlight.badgeLabel!,
          icon: Icons.star_outline,
          background: FlcColors.brand.withValues(alpha: 0.10),
          foreground: FlcColors.accent(context),
          dense: dense,
        );
      case EventHighlight.specialOffer:
        return _BadgeChip(
          label: highlight.badgeLabel!,
          icon: Icons.local_offer_outlined,
          background: FlcColors.warning.withValues(alpha: 0.14),
          // Light mode: warning darkened for AA contrast on the light
          // tint. Dark mode: plain warning already passes (~5.2:1) against
          // the dark surface — the darkened version does not (~2.7:1).
          foreground: Theme.of(context).brightness == Brightness.dark ? FlcColors.warning : const Color(0xFF7A5900),
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
