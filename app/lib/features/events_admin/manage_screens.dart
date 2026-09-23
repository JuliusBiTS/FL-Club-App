import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/profile_provider.dart';
import 'events_admin_providers.dart';

/// Staff area: every event (drafts, scheduled, live, past), with the shared
/// editor behind "New event" and each row. The route is redirect-guarded to
/// staff (app_router.dart) — that's a courtesy; Postgres refuses everything
/// a non-staff account tries regardless.
class ManageEventsScreen extends ConsumerWidget {
  const ManageEventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(currentProfileProvider).valueOrNull?.isAdmin ?? false;
    return EventsManagerScreen(repository: ref.watch(eventAdminRepositoryProvider), isAdmin: isAdmin);
  }
}

/// Staff area: send a general announcement and see what has gone out.
class ManageNotificationsScreen extends ConsumerWidget {
  const ManageNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NotificationsScreen(repository: ref.watch(eventAdminRepositoryProvider));
  }
}

/// Staff area: trigger a podcast/article resync, add or remove a YouTube
/// video manually — feedback: "how do you edit the media tab?"
class ManageMediaScreen extends ConsumerWidget {
  const ManageMediaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MediaContentScreen(repository: ref.watch(mediaAdminRepositoryProvider));
  }
}
