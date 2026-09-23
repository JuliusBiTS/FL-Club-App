import 'package:flutter/material.dart';

import '../theme/flc_colors.dart';
import '../theme/flc_spacing.dart';
import '../theme/flc_typography.dart';

/// A staff member's personal reason an event is worth attending — a speech
/// bubble with their photo, name and a short quote, Waterstones-style.
/// Independent of the FC Highlights / Staff pick / Special offer ribbon:
/// any event can carry one, or none.
class StaffPickBubble extends StatelessWidget {
  const StaffPickBubble({required this.name, required this.quote, this.photoUrl, this.dense = false, super.key});

  final String name;
  final String quote;
  final String? photoUrl;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final double avatarRadius = dense ? 16 : 20;
    return Container(
      padding: EdgeInsets.all(dense ? FlcSpace.sm : FlcSpace.md),
      decoration: BoxDecoration(
        color: FlcColors.brand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(FlcRadius.card),
        border: Border.all(color: FlcColors.brand.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: avatarRadius,
            backgroundColor: FlcColors.brand.withValues(alpha: 0.15),
            backgroundImage: photoUrl == null ? null : NetworkImage(photoUrl!),
            child: photoUrl == null ? Icon(Icons.person_outline, size: avatarRadius, color: FlcColors.accent(context)) : null,
          ),
          const SizedBox(width: FlcSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '"${quote.trim()}"',
                  style: (dense ? FlcTextStyles.bodySmall : FlcTextStyles.body).copyWith(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 2),
                Text(
                  '— $name, Frontline Club',
                  style: FlcTextStyles.caption.copyWith(color: FlcColors.accent(context), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
