import 'package:flc_core/flc_core.dart';
import 'package:flutter_test/flutter_test.dart';

EventDraft _validDraft() => EventDraft(
      title: 'Afghanistan 2026',
      summary: 'An updated look at power and exile.',
      category: 'Panel discussion',
      startsAt: DateTime(2027, 9, 9, 19, 0),
      heroImageUrl: 'https://example.com/hero.jpg',
      capacityTotal: 120,
      capacityApp: 100,
      capacityEventbrite: 20,
      speakers: <SpeakerDraft>[SpeakerDraft(name: 'Nomia Iqbal')],
      ticketTypes: <TicketTypeDraft>[
        TicketTypeDraft(name: 'Standard', priceMinor: 1500, quantity: 60),
        TicketTypeDraft(name: 'Member', audience: 'member', requiresMember: true, priceMinor: 500, quantity: 40),
      ],
    );

void main() {
  group('LondonTime', () {
    test('summer: 19:00 London is 18:00 UTC (BST)', () {
      expect(LondonTime.toUtc(DateTime(2026, 9, 9, 19)), DateTime.utc(2026, 9, 9, 18));
    });

    test('winter: 19:00 London is 19:00 UTC (GMT)', () {
      expect(LondonTime.toUtc(DateTime(2026, 12, 9, 19)), DateTime.utc(2026, 12, 9, 19));
    });

    test('UTC instant reads as London wall-clock time', () {
      final DateTime wall = LondonTime.fromUtc(DateTime.utc(2026, 9, 9, 18));
      expect((wall.hour, wall.minute), (19, 0));
    });

    test('2026 clock changes: 29 March and 25 October at 01:00 UTC', () {
      expect(LondonTime.isBst(DateTime.utc(2026, 3, 29, 0, 59)), isFalse);
      expect(LondonTime.isBst(DateTime.utc(2026, 3, 29, 1, 0)), isTrue);
      expect(LondonTime.isBst(DateTime.utc(2026, 10, 25, 0, 59)), isTrue);
      expect(LondonTime.isBst(DateTime.utc(2026, 10, 25, 1, 0)), isFalse);
    });

    test('every hour of 2026 round-trips (except the repeated autumn hour)', () {
      DateTime t = DateTime.utc(2026, 1, 1);
      while (t.year == 2026) {
        final bool repeatedHour = t.isAfter(DateTime.utc(2026, 10, 25, 0, 59)) && t.isBefore(DateTime.utc(2026, 10, 25, 2));
        if (!repeatedHour) {
          expect(LondonTime.toUtc(LondonTime.fromUtc(t)), t, reason: 'failed at $t');
        }
        t = t.add(const Duration(hours: 1));
      }
    });
  });

  group('EventText.markdownToHtml', () {
    test('paragraphs, bold, italic, links, lists, headings', () {
      final String html = EventText.markdownToHtml('## Why it matters\n\nA **bold** and *quiet* line.\nSecond line.\n\n- one\n- two\n\nRead [more](https://example.com/a).');
      expect(html, contains('<h2>Why it matters</h2>'));
      expect(html, contains('<p>A <strong>bold</strong> and <em>quiet</em> line.<br>Second line.</p>'));
      expect(html, contains('<ul><li>one</li><li>two</li></ul>'));
      expect(html, contains('<a href="https://example.com/a">more</a>'));
    });

    test('HTML typed into the box is escaped, never passed through', () {
      final String html = EventText.markdownToHtml('<script>alert(1)</script> <img src=x onerror=alert(1)>');
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<img')));
      expect(html, contains('&lt;script&gt;'));
    });

    test('javascript: links are not turned into links', () {
      final String html = EventText.markdownToHtml('[click](javascript:alert(1))');
      expect(html, isNot(contains('<a ')));
    });

    test('a quote cannot break out of the href attribute', () {
      final String html = EventText.markdownToHtml('[x](https://a.com/"onmouseover="alert(1))');
      final String tag = RegExp(r'<a [^>]*>').firstMatch(html)!.group(0)!;
      // The typed quotes are entity-escaped, so the tag keeps exactly one
      // attribute (href) with exactly two real quote characters.
      expect('"'.allMatches(tag).length, 2);
      expect(tag, startsWith('<a href="'));
      expect(tag, endsWith('">'));
      expect(tag, contains('&quot;'));
    });

    test('empty input gives empty output', () {
      expect(EventText.markdownToHtml('   \n  '), '');
    });
  });

  group('EventText helpers', () {
    test('slugify', () {
      expect(EventText.slugify('Afghanistan 2026', DateTime(2026, 9, 9)), 'afghanistan-2026-20260909');
      expect(EventText.slugify('Screening + Q&A: Life Support!', null), 'screening-q-and-a-life-support');
      expect(EventText.slugify('!!!', null), 'event');
    });

    test('stripHtml gives readable text', () {
      expect(EventText.stripHtml('<p>Hello &amp; welcome</p><ul><li>a</li><li>b</li></ul>'), 'Hello & welcome\n\n- a\n- b');
    });
  });

  group('EventDraft.validate', () {
    test('a complete draft is publishable with nothing to fix', () {
      final EventIssues issues = _validDraft().validate(publishing: true);
      expect(issues.errors, isEmpty);
      expect(issues.warnings, isEmpty);
    });

    test('a blank draft needs a title and a date', () {
      final EventIssues issues = EventDraft().validate(publishing: false);
      expect(issues.errors, containsAll(<String>['Give the event a title.', 'Pick a start date and time.']));
    });

    test('app + Eventbrite capacity cannot exceed the total', () {
      final EventDraft d = _validDraft()..capacityApp = 110;
      expect(d.validate(publishing: false).errors.join(' '), contains('is more than the total'));
    });

    test('ticket quantities cannot exceed what is allocated to the app', () {
      final EventDraft d = _validDraft()..ticketTypes.first.quantity = 90;
      expect(d.validate(publishing: false).errors.join(' '), contains('only 100 are allocated'));
    });

    test('quantity cannot drop below tickets already sold', () {
      final EventDraft d = _validDraft()
        ..ticketTypes.first.sold = 30
        ..ticketTypes.first.quantity = 20;
      expect(d.validate(publishing: false).errors.join(' '), contains('30 sold'));
    });

    test('total capacity cannot drop below tickets already sold (existing event)', () {
      final EventDraft d = _validDraft()
        ..id = 'abc'
        ..issuedTickets = 70
        ..eventbriteSold = 15
        ..capacityTotal = 80
        ..capacityApp = 60
        ..capacityEventbrite = 20;
      expect(d.validate(publishing: false).errors.join(' '), contains('already sold'));
    });

    test('links need https and a label', () {
      final EventDraft d = _validDraft()..links = <LinkDraft>[LinkDraft(label: 'Buy', url: 'not a url')];
      expect(d.validate(publishing: false).errors.join(' '), contains('https://'));
    });

    test('an online event needs its livestream link to publish (but not to save a draft)', () {
      final EventDraft d = _validDraft()..isOnline = true;
      expect(d.validate(publishing: true).errors.join(' '), contains('livestream'));
      expect(d.validate(publishing: false).errors, isEmpty);
    });

    test('at most four perks', () {
      final EventDraft d = _validDraft()..perks = <String>['a', 'b', 'c', 'd', 'e'];
      expect(d.validate(publishing: false).errors.join(' '), contains('at most 4'));
    });

    test('missing picture / summary are warnings, not blockers', () {
      final EventDraft d = _validDraft()
        ..heroImageUrl = null
        ..summary = '';
      final EventIssues issues = d.validate(publishing: true);
      expect(issues.ok, isTrue);
      expect(issues.warnings.length, 2);
    });
  });

  group('EventDraft.toEventRow', () {
    test('writes UTC times, generated HTML and the highlight wire value', () {
      final EventDraft d = _validDraft()
        ..descriptionMd = 'Hello **world**'
        ..highlight = EventHighlight.fcRecommends
        ..perks = <String>['Free drink with your ticket'];
      final Map<String, dynamic> row = d.toEventRow(forStatus: 'published');

      expect(row['starts_at'], DateTime.utc(2027, 9, 9, 18).toIso8601String()); // 19:00 BST
      expect(row['description_html'], '<p>Hello <strong>world</strong></p>');
      expect(row['highlight'], 'fc_recommends');
      expect(row['perks'], <String>['Free drink with your ticket']);
      expect(row['status'], 'published');
      expect(row['timezone'], 'Europe/London');
    });

    test('blank optional text becomes null, not empty strings', () {
      final Map<String, dynamic> row = _validDraft().toEventRow(forStatus: 'draft');
      expect(row['subtitle'], isNull);
      expect(row['venue_room'], isNull);
      expect(row['description_html'], isNull);
    });

    test('duplicated() is a fresh draft a week later with no sales or promotion carried over', () {
      final EventDraft original = _validDraft()
        ..id = 'abc'
        ..status = 'published'
        ..highlight = EventHighlight.fcRecommends
        ..ticketTypes.first.sold = 10;
      final EventDraft copy = original.duplicated();
      expect(copy.id, isNull);
      expect(copy.status, 'draft');
      expect(copy.startsAt, DateTime(2027, 9, 16, 19));
      expect(copy.highlight, EventHighlight.none);
      expect(copy.ticketTypes.every((TicketTypeDraft t) => t.id == null && t.sold == 0), isTrue);
    });
  });

  group('EventModel', () {
    test('parses a row with the new fields, and an old row without them', () {
      final EventModel full = EventModel.fromJson(<String, dynamic>{
        'id': '1',
        'slug': 's',
        'title': 'T',
        'starts_at': '2026-09-09T18:00:00Z',
        'highlight': 'special_offer',
        'perks': <String>['Free drink with your ticket'],
        'speakers': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'A', 'role': 'Reporter', 'photo_url': 'https://x/y.jpg'},
        ],
        'links': <Map<String, dynamic>>[
          <String, dynamic>{'label': 'Buy the book', 'url': 'https://x', 'kind': 'book'},
        ],
      });
      expect(full.highlight, EventHighlight.specialOffer);
      expect(full.speakers.single.photoUrl, 'https://x/y.jpg');
      expect(full.links.single.kind, 'book');
      expect(full.loyaltyEligible, isTrue);

      final EventModel old = EventModel.fromJson(<String, dynamic>{'id': '2', 'slug': 's2', 'title': 'Old', 'starts_at': '2026-09-09T18:00:00Z'});
      expect(old.highlight, EventHighlight.none);
      expect(old.speakers, isEmpty);
      expect(old.perks, isEmpty);
    });

    test('an unknown highlight value from the server degrades to none', () {
      final EventModel e = EventModel.fromJson(<String, dynamic>{'id': '3', 'slug': 's3', 'title': 'X', 'starts_at': '2026-09-09T18:00:00Z', 'highlight': 'something_new'});
      expect(e.highlight, EventHighlight.none);
    });
  });
}
