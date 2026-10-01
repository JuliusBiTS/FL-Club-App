import 'package:flutter_test/flutter_test.dart';
import 'package:frontline_club_app/core/calendar/ics.dart';

void main() {
  final IcsEvent event = IcsEvent(
    uid: 'abc@frontlineclub',
    title: 'Panel: War, Law; and "Truth"',
    startsAt: DateTime.utc(2026, 10, 3, 17),
    endsAt: DateTime.utc(2026, 10, 3, 18, 30),
    location: 'The Forum, 13 Norfolk Place, London',
    description: 'Line one\nLine two',
  );

  test('writes a valid VEVENT with UTC times and escaped text', () {
    final String ics = buildIcs(event, now: DateTime.utc(2026, 9, 30, 12));
    expect(ics, contains('BEGIN:VCALENDAR'));
    expect(ics, contains('DTSTART:20261003T170000Z'));
    expect(ics, contains('DTEND:20261003T183000Z'));
    expect(ics, contains(r'SUMMARY:Panel: War\, Law\; and "Truth"'));
    expect(ics, contains(r'LOCATION:The Forum\, 13 Norfolk Place\, London'));
    expect(ics, contains(r'DESCRIPTION:Line one\nLine two'));
    expect(ics, contains('TRIGGER:-PT60M'));
    expect(ics.endsWith('END:VCALENDAR\r\n'), isTrue);
  });

  test('defaults to a two hour event when there is no end time', () {
    final String ics = buildIcs(
      IcsEvent(uid: 'x', title: 'T', startsAt: DateTime.utc(2026, 10, 3, 17)),
      now: DateTime.utc(2026, 9, 30),
    );
    expect(ics, contains('DTEND:20261003T190000Z'));
  });

  test('folds long lines at 75 characters', () {
    final String ics = buildIcs(
      IcsEvent(uid: 'x', title: 'A' * 200, startsAt: DateTime.utc(2026, 10, 3, 17)),
      now: DateTime.utc(2026, 9, 30),
    );
    for (final String line in ics.split('\r\n')) {
      expect(line.length <= 75, isTrue, reason: line);
    }
  });

  test('Google Calendar link carries title, dates and place', () {
    final Uri url = googleCalendarUrl(event);
    expect(url.host, 'calendar.google.com');
    expect(url.queryParameters['text'], 'Panel: War, Law; and "Truth"');
    expect(url.queryParameters['dates'], '20261003T170000Z/20261003T183000Z');
    expect(url.queryParameters['location'], contains('The Forum'));
  });
}
