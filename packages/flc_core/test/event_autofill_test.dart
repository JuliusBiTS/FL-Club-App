import 'package:flc_core/flc_core.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fullResponse() => <String, dynamic>{
      'title': 'Reporting from the Edge of the Map',
      'subtitle': 'What it takes to cover a story nobody else can reach',
      'summary': 'Three reporters on working alone and staying safe.',
      'description_md': 'Freelancers now cover most of the hardest stories.\n\n- one\n- two',
      'category': 'Panel discussion',
      'tags': <String>['Press freedom', 'Freelancers'],
      'starts_at': '2026-10-14T19:00:00',
      'ends_at': '2026-10-14T21:00:00',
      'doors_at': '2026-10-14T18:30:00',
      'venue_room': 'The Forum',
      'venue_address': null,
      'is_online': false,
      'livestream_url': null,
      'speakers': <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Priya Nair', 'role': 'Correspondent', 'bio': null},
      ],
      'links': <Map<String, dynamic>>[
        <String, dynamic>{'label': 'Read more', 'url': 'https://example.com', 'kind': 'article'},
      ],
      'perks': <String>['Free drink with your ticket'],
      'notes': <String>['Exact end time was a guess.'],
    };

void main() {
  group('ExtractedEventFields.fromJson', () {
    test('parses a full response', () {
      final ExtractedEventFields f = ExtractedEventFields.fromJson(_fullResponse());
      expect(f.title, 'Reporting from the Edge of the Map');
      expect(f.category, 'Panel discussion');
      expect(f.tags, <String>['Press freedom', 'Freelancers']);
      expect((f.startsAt!.hour, f.startsAt!.minute), (19, 0));
      expect(f.speakers.length, 1);
      expect(f.links.single.kind, 'article');
      expect(f.notes, <String>['Exact end time was a guess.']);
      expect(f.isEmpty, isFalse);
    });

    test('an all-null/empty response is empty and never throws', () {
      final ExtractedEventFields f = ExtractedEventFields.fromJson(<String, dynamic>{
        'title': null, 'subtitle': null, 'summary': null, 'description_md': null,
        'category': null, 'tags': <String>[], 'starts_at': null, 'ends_at': null,
        'doors_at': null, 'venue_room': null, 'venue_address': null, 'is_online': false,
        'livestream_url': null, 'speakers': <dynamic>[], 'links': <dynamic>[],
        'perks': <String>[], 'notes': <String>[],
      });
      expect(f.isEmpty, isTrue);
    });

    test('a malformed speaker/link (missing name/url) is dropped, not a crash', () {
      final ExtractedEventFields f = ExtractedEventFields.fromJson(<String, dynamic>{
        ..._fullResponse(),
        'speakers': <Map<String, dynamic>>[
          <String, dynamic>{'role': 'No name here'},
          <String, dynamic>{'name': 'Valid One'},
        ],
        'links': <Map<String, dynamic>>[
          <String, dynamic>{'label': 'No url'},
        ],
      });
      expect(f.speakers.length, 1);
      expect(f.speakers.single.name, 'Valid One');
      expect(f.links, isEmpty);
    });

    test('an unrecognised link kind falls back safely at apply time, not at parse time', () {
      final ExtractedEventFields f = ExtractedEventFields.fromJson(<String, dynamic>{
        ..._fullResponse(),
        'links': <Map<String, dynamic>>[
          <String, dynamic>{'label': 'Odd', 'url': 'https://example.com', 'kind': 'something_new'},
        ],
      });
      expect(f.links.single.kind, 'something_new'); // parsed as-is
    });
  });

  group('ExtractedEventFields.applyTo', () {
    test('fills every blank field on an empty draft', () {
      final EventDraft draft = EventDraft();
      final AutoFillResult r = ExtractedEventFields.fromJson(_fullResponse()).applyTo(draft);

      expect(draft.title, 'Reporting from the Edge of the Map');
      expect(draft.subtitle, isNotEmpty);
      expect(draft.category, 'Panel discussion');
      expect(draft.startsAt, isNotNull);
      expect(draft.venueRoom, 'The Forum');
      expect(draft.tags, <String>['Press freedom', 'Freelancers']);
      expect(draft.speakers.single.name, 'Priya Nair');
      expect(draft.links.single.label, 'Read more');
      expect(draft.perks, <String>['Free drink with your ticket']);
      expect(r.filled, isNotEmpty);
      expect(r.keptExisting, isEmpty);
      expect(r.notes, <String>['Exact end time was a guess.']);
    });

    test('never overwrites a field the person already filled in by hand', () {
      final EventDraft draft = EventDraft(
        title: 'My own title',
        category: 'Book talk',
        startsAt: DateTime(2027, 1, 1, 20),
        speakers: <SpeakerDraft>[SpeakerDraft(name: 'Someone Else')],
      );
      final AutoFillResult r = ExtractedEventFields.fromJson(_fullResponse()).applyTo(draft);

      expect(draft.title, 'My own title');
      expect(draft.category, 'Book talk');
      expect(draft.startsAt, DateTime(2027, 1, 1, 20));
      expect(draft.speakers.single.name, 'Someone Else');
      // But blank fields still get filled from the same response.
      expect(draft.venueRoom, 'The Forum');
      expect(r.keptExisting, containsAll(<String>['Title', 'Category', 'Start date & time', 'Speakers']));
    });

    test('tags are additive: existing tags are kept and new ones appended, no duplicates', () {
      final EventDraft draft = EventDraft(tags: <String>['Press freedom', 'Custom tag']);
      ExtractedEventFields.fromJson(_fullResponse()).applyTo(draft);
      expect(draft.tags, <String>['Press freedom', 'Custom tag', 'Freelancers']);
    });

    test('perks respect the 4-perk cap and never duplicate', () {
      final EventDraft draft = EventDraft(perks: <String>['a', 'b', 'c']);
      final AutoFillResult r = ExtractedEventFields.fromJson(_fullResponse()).applyTo(draft);
      expect(draft.perks, <String>['a', 'b', 'c', 'Free drink with your ticket']);
      expect(r.filled, contains('1 perk'));

      final EventDraft full = EventDraft(perks: <String>['a', 'b', 'c', 'd']);
      final AutoFillResult r2 = ExtractedEventFields.fromJson(_fullResponse()).applyTo(full);
      expect(full.perks, <String>['a', 'b', 'c', 'd']);
      expect(r2.keptExisting, contains('Perks'));
    });

    test('isOnline only ever turns on, never off', () {
      final EventDraft draft = EventDraft(isOnline: true);
      ExtractedEventFields.fromJson(<String, dynamic>{..._fullResponse(), 'is_online': false}).applyTo(draft);
      expect(draft.isOnline, isTrue); // untouched, not turned off
    });

    test('price, capacity and ticket types are never touched, whatever is pasted', () {
      final EventDraft draft = EventDraft(capacityTotal: 999, capacityApp: 999);
      final Map<String, dynamic> json = Map<String, dynamic>.from(_fullResponse());
      // Even if a caller somehow slipped these keys in, there's no code path
      // that reads them — applyTo has no capacity/price logic at all.
      json['price_minor'] = 1;
      json['capacity_total'] = 1;
      ExtractedEventFields.fromJson(json).applyTo(draft);
      expect(draft.capacityTotal, 999);
      expect(draft.capacityApp, 999);
      expect(draft.ticketTypes, isEmpty);
    });

    test('an empty extraction result changes nothing and reports isEmpty', () {
      final ExtractedEventFields empty = ExtractedEventFields.fromJson(<String, dynamic>{
        'title': null, 'subtitle': null, 'summary': null, 'description_md': null,
        'category': null, 'tags': <String>[], 'starts_at': null, 'ends_at': null,
        'doors_at': null, 'venue_room': null, 'venue_address': null, 'is_online': false,
        'livestream_url': null, 'speakers': <dynamic>[], 'links': <dynamic>[],
        'perks': <String>[], 'notes': <String>[],
      });
      final EventDraft draft = EventDraft();
      final AutoFillResult r = empty.applyTo(draft);
      expect(r.isEmpty, isTrue);
      expect(draft.title, isEmpty);
    });
  });
}
