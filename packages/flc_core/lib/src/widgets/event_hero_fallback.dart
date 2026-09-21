import 'package:flutter/material.dart';

import '../theme/flc_colors.dart';
import '../theme/flc_spacing.dart';
import '../theme/flc_typography.dart';

/// An icon that stands for an event category (matches kEventCategories).
IconData eventCategoryIcon(String? category) {
  final String c = (category ?? '').toLowerCase();
  if (c.contains('book')) return Icons.menu_book_outlined;
  if (c.contains('screening')) return Icons.movie_outlined;
  if (c.contains('online')) return Icons.live_tv_outlined;
  if (c.contains('workshop') || c.contains('training')) return Icons.school_outlined;
  if (c.contains('social')) return Icons.local_bar_outlined;
  if (c.contains('exhibition')) return Icons.photo_camera_outlined;
  if (c.contains('award') || c.contains('fundrais')) return Icons.emoji_events_outlined;
  if (c.contains('private')) return Icons.meeting_room_outlined;
  if (c.contains('panel')) return Icons.forum_outlined;
  return Icons.event_outlined;
}

/// What an event shows in place of a picture: the brand olive with a large,
/// quiet category icon and the category name. It makes an event that has no
/// photo yet look deliberate rather than broken — in the app's feed and event
/// page, and in the editor's preview.
class EventHeroFallback extends StatelessWidget {
  const EventHeroFallback({this.category, this.showLabel = true, super.key});

  final String? category;

  /// The category name in the corner — hide it on small thumbnails.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = constraints.biggest.shortestSide.isFinite ? constraints.biggest.shortestSide : 120;
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[FlcColors.brand, Color(0xFF1F2C07)],
            ),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                right: -side * 0.08,
                bottom: -side * 0.12,
                child: Icon(eventCategoryIcon(category), size: side * 0.85, color: Colors.white.withValues(alpha: 0.10)),
              ),
              if (showLabel && category != null && category!.isNotEmpty)
                Positioned(
                  left: FlcSpace.md,
                  bottom: FlcSpace.sm,
                  child: Text(category!.toUpperCase(), style: FlcTextStyles.overline.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                ),
            ],
          ),
        );
      },
    );
  }
}
