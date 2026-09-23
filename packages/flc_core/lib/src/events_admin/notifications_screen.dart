import 'package:flutter/material.dart';

import '../theme/flc_colors.dart';
import '../theme/flc_spacing.dart';
import '../theme/flc_typography.dart';
import 'event_admin_repository.dart';
import 'sections/promotion_sections.dart';
import 'sections/push_composer.dart';
import 'widgets/editor_widgets.dart';

/// General club announcements (not tied to one event) plus everything sent
/// recently. Shared by the admin console and the app's staff area.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({required this.repository, this.embedded = false, super.key});

  final EventAdminRepository repository;

  /// True inside the admin console's shell (no app bar of its own).
  final bool embedded;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<Map<String, dynamic>>> _history = widget.repository.pushCampaigns(limit: 40);

  void _reload() => setState(() => _history = widget.repository.pushCampaigns(limit: 40));

  @override
  Widget build(BuildContext context) {
    final double gutter = widget.embedded ? FlcSpace.xl : FlcSpace.md;

    final Widget body = ListView(
      padding: EdgeInsets.all(gutter),
      children: <Widget>[
        if (widget.embedded) ...<Widget>[
          Text('Notifications', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: FlcSpace.md),
        ],
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionCard(
                  title: 'Send an announcement',
                  subtitle: 'For news that isn\'t about one event. To promote an event, use the Notifications section inside that event.',
                  child: PushComposer(repository: widget.repository, onSent: _reload),
                ),
                const Text('Recently sent', style: FlcTextStyles.h3),
                const SizedBox(height: FlcSpace.xs),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _history,
                  builder: (BuildContext context, AsyncSnapshot<List<Map<String, dynamic>>> snap) {
                    if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(FlcSpace.md), child: LinearProgressIndicator());
                    if (snap.hasError) {
                      return Text('Couldn\'t load history. ${EventAdminRepository.describeError(snap.error!)}', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.error));
                    }
                    final List<Map<String, dynamic>> rows = snap.data ?? const <Map<String, dynamic>>[];
                    if (rows.isEmpty) return Text('Nothing sent yet.', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)));
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.xs),
                        child: Column(children: <Widget>[for (final Map<String, dynamic> r in rows) CampaignTile(row: r)]),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: body,
    );
  }
}
