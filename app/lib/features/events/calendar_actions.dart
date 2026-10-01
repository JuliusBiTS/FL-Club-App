import 'dart:io';

import 'package:flc_core/flc_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/calendar/ics.dart';

IcsEvent icsFromEvent(EventModel e) {
  final String place = <String>[
    if (e.venueRoom != null && e.venueRoom!.trim().isNotEmpty) e.venueRoom!.trim(),
    e.venueName,
    e.venueAddress,
  ].where((String s) => s.trim().isNotEmpty).join(', ');
  return IcsEvent(
    uid: '${e.id}@frontlineclub.app',
    title: e.title,
    startsAt: e.startsAt,
    endsAt: e.endsAt,
    location: e.isOnline && place.isEmpty ? 'Online' : place,
    description: <String>[
      if (e.summary != null && e.summary!.trim().isNotEmpty) e.summary!.trim(),
      if (e.isOnline && (e.livestreamUrl ?? '').isNotEmpty) 'Watch online: ${e.livestreamUrl}',
      'Tickets and details are in the Frontline Club app.',
    ].join('\n\n'),
  );
}

IcsEvent icsFromTicket(TicketModel t) {
  final String place = <String>[
    if (t.venueRoom != null && t.venueRoom!.trim().isNotEmpty) t.venueRoom!.trim(),
    t.venueName,
    t.venueAddress,
  ].where((String s) => s.trim().isNotEmpty).join(', ');
  return IcsEvent(
    uid: '${t.eventId}@frontlineclub.app',
    title: t.eventTitle,
    startsAt: t.eventStartsAt,
    location: place,
    description: 'Your ticket is in the Frontline Club app: You → My tickets.',
  );
}

/// Hands the event to the phone's calendar. On a phone that's a share sheet
/// with an .ics file (Google Calendar, Samsung, Outlook… all take it); in a
/// browser, or if sharing isn't possible, it opens an "add to Google Calendar"
/// page instead.
Future<void> addToCalendar(BuildContext context, IcsEvent event) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (!kIsWeb) {
      final Directory dir = await getTemporaryDirectory();
      final File file = File(p.join(dir.path, 'frontline-event.ics'));
      await file.writeAsString(buildIcs(event), flush: true);
      await Share.shareXFiles(<XFile>[XFile(file.path, mimeType: 'text/calendar')], subject: event.title);
      return;
    }
  } catch (_) {
    // fall through to the web link
  }
  final bool opened = await launchUrl(googleCalendarUrl(event), mode: LaunchMode.externalApplication);
  if (!opened) {
    messenger.showSnackBar(const SnackBar(content: Text("Couldn't open a calendar. Try again in a moment.")));
  }
}
