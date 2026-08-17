import 'package:flutter/material.dart';

import '../../core/widgets/placeholder_screen.dart';

/// Episode list + player — briefing §9.8. RSS-sourced, background playback
/// via just_audio + audio_service, no account required.
class PodcastScreen extends StatelessWidget {
  const PodcastScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(title: 'Podcast', milestone: 'M8');
}
