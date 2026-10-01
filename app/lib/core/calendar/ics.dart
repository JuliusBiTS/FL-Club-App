/// Builds an iCalendar (.ics) file for one event, so it can be added to any
/// calendar app (Google, Apple, Outlook, Samsung…). Pure Dart — no plugin — so
/// it is easy to test and behaves the same everywhere.
class IcsEvent {
  const IcsEvent({
    required this.uid,
    required this.title,
    required this.startsAt,
    this.endsAt,
    this.location,
    this.description,
    this.reminderBefore = const Duration(hours: 1),
  });

  final String uid;
  final String title;
  final DateTime startsAt;

  /// Defaults to two hours after the start when the event has no end time.
  final DateTime? endsAt;
  final String? location;
  final String? description;
  final Duration? reminderBefore;
}

String buildIcs(IcsEvent e, {DateTime? now}) {
  final DateTime end = e.endsAt ?? e.startsAt.add(const Duration(hours: 2));
  final List<String> lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Frontline Club//App//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:${e.uid}',
    'DTSTAMP:${_utc(now ?? DateTime.now())}',
    'DTSTART:${_utc(e.startsAt)}',
    'DTEND:${_utc(end)}',
    'SUMMARY:${_escape(e.title)}',
    if (e.location != null && e.location!.trim().isNotEmpty) 'LOCATION:${_escape(e.location!)}',
    if (e.description != null && e.description!.trim().isNotEmpty) 'DESCRIPTION:${_escape(e.description!)}',
    if (e.reminderBefore != null) ...<String>[
      'BEGIN:VALARM',
      'ACTION:DISPLAY',
      'DESCRIPTION:${_escape(e.title)}',
      'TRIGGER:-PT${e.reminderBefore!.inMinutes}M',
      'END:VALARM',
    ],
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return '${lines.map(_fold).join('\r\n')}\r\n';
}

/// A "add this to Google Calendar" link — the fallback where a file can't be
/// shared (e.g. a desktop browser).
Uri googleCalendarUrl(IcsEvent e) {
  final DateTime end = e.endsAt ?? e.startsAt.add(const Duration(hours: 2));
  return Uri.https('calendar.google.com', '/calendar/render', <String, String>{
    'action': 'TEMPLATE',
    'text': e.title,
    'dates': '${_utc(e.startsAt)}/${_utc(end)}',
    if (e.location != null && e.location!.trim().isNotEmpty) 'location': e.location!,
    if (e.description != null && e.description!.trim().isNotEmpty) 'details': e.description!,
  });
}

String _utc(DateTime t) {
  final DateTime u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

/// RFC 5545 §3.3.11: backslash, semicolon, comma and newlines must be escaped.
String _escape(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll('\r\n', r'\n')
    .replaceAll('\n', r'\n');

/// RFC 5545 §3.1: lines are at most 75 octets; continuation lines start with a space.
String _fold(String line) {
  final List<int> bytes = line.codeUnits;
  if (bytes.length <= 75) return line;
  final StringBuffer out = StringBuffer();
  int i = 0;
  bool first = true;
  while (i < line.length) {
    final int take = first ? 75 : 74;
    final int end = (i + take) > line.length ? line.length : i + take;
    if (!first) out.write('\r\n ');
    out.write(line.substring(i, end));
    i = end;
    first = false;
  }
  return out.toString();
}
