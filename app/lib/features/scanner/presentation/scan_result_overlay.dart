import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';

/// Full-screen flash shown after every scan — briefing §16.1: "always
/// dark-surfaced regardless of theme... a white flash in a darkened Forum
/// is genuinely unpleasant." Tap-to-dismiss and auto-dismiss both resume
/// scanning; nothing here blocks the queue on staff interaction.
class ScanResultOverlay extends StatelessWidget {
  const ScanResultOverlay({
    required this.tone,
    required this.icon,
    required this.title,
    this.subtitle,
    this.detail,
    this.photoUrl,
    this.onDismiss,
    super.key,
  });

  final Color tone;
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? detail;
  final String? photoUrl;
  final VoidCallback? onDismiss;

  factory ScanResultOverlay.valid({
    required String title,
    String? subtitle,
    String? photoUrl,
    VoidCallback? onDismiss,
  }) =>
      ScanResultOverlay(
        tone: FlcColors.scannerValidBg,
        icon: Icons.check_circle_outline,
        title: title,
        subtitle: subtitle,
        photoUrl: photoUrl,
        onDismiss: onDismiss,
      );

  factory ScanResultOverlay.warning({
    required String title,
    String? subtitle,
    String? detail,
    String? photoUrl,
    VoidCallback? onDismiss,
  }) =>
      ScanResultOverlay(
        tone: FlcColors.scannerWarningBg,
        icon: Icons.error_outline,
        title: title,
        subtitle: subtitle,
        detail: detail,
        photoUrl: photoUrl,
        onDismiss: onDismiss,
      );

  factory ScanResultOverlay.error({required String title, String? subtitle, VoidCallback? onDismiss}) =>
      ScanResultOverlay(
        tone: FlcColors.scannerErrorBg,
        icon: Icons.cancel_outlined,
        title: title,
        subtitle: subtitle,
        onDismiss: onDismiss,
      );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: ColoredBox(
        color: tone,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(FlcSpace.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (photoUrl != null) ...<Widget>[
                    ClipOval(
                      child: Image.network(
                        photoUrl!,
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.person, size: 80, color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: FlcSpace.md),
                  ] else
                    Icon(icon, size: 80, color: Colors.white),
                  const SizedBox(height: FlcSpace.md),
                  Text(
                    title,
                    style: FlcTextStyles.h2.copyWith(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: FlcSpace.xs),
                    Text(
                      subtitle!,
                      style: FlcTextStyles.body.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (detail != null) ...<Widget>[
                    const SizedBox(height: FlcSpace.sm),
                    Text(
                      detail!,
                      style: FlcTextStyles.bodySmall.copyWith(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: FlcSpace.lg),
                  Text(
                    'Tap anywhere to continue',
                    style: FlcTextStyles.bodySmall.copyWith(color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
