import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontline_club_app/core/auth/profile_provider.dart';
import 'package:frontline_club_app/features/events/events_providers.dart';
import 'package:frontline_club_app/features/events/presentation/event_detail_screen.dart';
import 'package:frontline_club_app/features/events/presentation/events_feed_controller.dart';
import 'package:frontline_club_app/features/events/presentation/events_feed_screen.dart';

class _FakeFeed extends EventsFeedController {
  _FakeFeed(this.events);

  final List<EventModel> events;

  @override
  Future<List<EventModel>> build() async => events;

  @override
  Future<void> refresh() async {}
}

final DateTime _soon = DateTime.now().toUtc().add(const Duration(days: 4));

final List<EventModel> _events = <EventModel>[
  EventModel(id: '1', slug: 'panel', title: 'Afghanistan 2026', startsAt: _soon, status: 'published', category: 'Panel discussion'),
  EventModel(
    id: '2',
    slug: 'book',
    title: 'Book talk: The Last Correspondent',
    startsAt: _soon.add(const Duration(days: 2)),
    status: 'published',
    category: 'Book talk',
    highlight: EventHighlight.fcRecommends,
    perks: <String>['Free drink with your ticket'],
  ),
  EventModel(id: '3', slug: 'quiz', title: 'Members\' quiz night', startsAt: _soon.add(const Duration(days: 20)), status: 'published', category: 'Members\' social', membersOnly: true),
];

ProfileModel _profile(UserRole role) => ProfileModel(id: 'u1', email: 'a@b.c', role: role);

Future<void> _pumpFeed(WidgetTester tester, {UserRole? role}) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        eventsFeedControllerProvider.overrideWith(() => _FakeFeed(_events)),
        sellingFastIdsProvider.overrideWith((ref) async => <String>{'1'}),
        currentProfileProvider.overrideWith((ref) async => role == null ? null : _profile(role)),
      ],
      child: MaterialApp(theme: FlcTheme.light(), home: const EventsFeedScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Events feed', () {
    testWidgets('lifts FC Recommends into its own section at the top', (tester) async {
      await _pumpFeed(tester);

      expect(find.text('FC RECOMMENDS'), findsOneWidget); // section header
      expect(find.text('COMING UP'), findsOneWidget);

      final recommendedY = tester.getTopLeft(find.text('Book talk: The Last Correspondent')).dy;
      final panelY = tester.getTopLeft(find.text('Afghanistan 2026')).dy;
      expect(recommendedY, lessThan(panelY), reason: 'the recommended event is listed first even though it is later in date');
    });

    testWidgets('shows ribbons: FC Recommends, a perk, and a derived "Selling fast"', (tester) async {
      await _pumpFeed(tester);

      expect(find.text('FC Recommends'), findsOneWidget); // the badge (header is upper-case)
      expect(find.text('Free drink with your ticket'), findsOneWidget);
      expect(find.text('Selling fast'), findsOneWidget);
      expect(find.text('Members only'), findsWidgets);
    });

    testWidgets('builds a chip for each category in the programme and filters by it', (tester) async {
      await _pumpFeed(tester);

      expect(find.widgetWithText(ChoiceChip, 'Panel discussion'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Book talk'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Book talk'));
      await tester.pumpAndSettle();
      expect(find.text('Book talk: The Last Correspondent'), findsOneWidget);
      expect(find.text('Afghanistan 2026'), findsNothing);
    });

    testWidgets('the Offers chip shows events with a special offer or perks', (tester) async {
      await _pumpFeed(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Offers'));
      await tester.pumpAndSettle();
      expect(find.text('Book talk: The Last Correspondent'), findsOneWidget);
      expect(find.text('Members\' quiz night'), findsNothing);
    });

    testWidgets('only staff see the "Manage events" button', (tester) async {
      await _pumpFeed(tester);
      expect(find.byTooltip('Manage events'), findsNothing);

      await _pumpFeed(tester, role: UserRole.user);
      expect(find.byTooltip('Manage events'), findsNothing);

      await _pumpFeed(tester, role: UserRole.staff);
      expect(find.byTooltip('Manage events'), findsOneWidget);
    });
  });

  group('Event page', () {
    final event = EventModel(
      id: '2',
      slug: 'book',
      title: 'Book talk: The Last Correspondent',
      subtitle: 'A novel of fixers and front lines',
      summary: 'Short summary.',
      descriptionHtml: '<p>An evening with the <strong>author</strong>.</p>',
      startsAt: DateTime.utc(2026, 9, 30, 18), // 19:00 BST
      endsAt: DateTime.utc(2026, 9, 30, 20),
      doorsAt: DateTime.utc(2026, 9, 30, 17, 30),
      status: 'published',
      category: 'Book talk',
      highlight: EventHighlight.specialOffer,
      perks: <String>['Signed copies available'],
      speakers: <EventSpeaker>[const EventSpeaker(name: 'Helena Marsh', role: 'Author', bio: 'Writes about the people behind the byline.')],
      links: <EventLink>[const EventLink(label: 'Buy the book', url: 'https://example.com/book', kind: 'book')],
      tags: <String>['Fiction'],
    );

    Future<void> pumpDetail(WidgetTester tester, EventModel e, {UserRole? role}) async {
      tester.view.physicalSize = const Size(420, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            eventDetailProvider.overrideWith((ref, slug) async => e),
            ticketTypesProvider.overrideWith(
              (ref, id) async => <TicketTypeModel>[
                const TicketTypeModel(id: 't1', eventId: '2', name: 'Standard', priceMinor: 1500, quantity: 50),
                const TicketTypeModel(id: 't2', eventId: '2', name: 'Member', priceMinor: 500, quantity: 20, audience: 'member', requiresMember: true),
              ],
            ),
            sellingFastIdsProvider.overrideWith((ref) async => <String>{}),
            currentProfileProvider.overrideWith((ref) async => role == null ? null : _profile(role)),
          ],
          child: MaterialApp(theme: FlcTheme.light(), home: EventDetailScreen(slug: e.slug)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows everything entered in the editor, with times in London time', (tester) async {
      await pumpDetail(tester, event);

      expect(find.text('A novel of fixers and front lines'), findsOneWidget);
      expect(find.text('Wednesday 30 September 2026'), findsOneWidget);
      // 18:00 UTC in September is 19:00 in London (BST) — never the device's or UTC's hour.
      expect(find.textContaining('Doors 18:30 · Starts 19:00 – 21:00'), findsOneWidget);
      expect(find.text('Special offer'), findsOneWidget);
      expect(find.text('Signed copies available'), findsOneWidget);
      expect(find.text('Helena Marsh'), findsOneWidget);
      expect(find.text('Author'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Buy the book'), findsOneWidget);
      expect(find.text('Earns a loyalty point'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
    });

    testWidgets('an event that doesn\'t earn loyalty says nothing about points', (tester) async {
      await pumpDetail(tester, event.copyWith(loyaltyEligible: false));
      expect(find.textContaining('loyalty point'), findsNothing);
    });

    testWidgets('a cancelled event shows a banner and no tickets', (tester) async {
      await pumpDetail(tester, event.copyWith(status: 'cancelled'));

      expect(find.text('This event has been cancelled.'), findsOneWidget);
      expect(find.text('Tickets'), findsNothing);
      expect(find.text('Standard'), findsNothing);
    });

    testWidgets('only staff get an Edit button', (tester) async {
      await pumpDetail(tester, event);
      expect(find.byTooltip('Edit this event'), findsNothing);

      await pumpDetail(tester, event, role: UserRole.staff);
      expect(find.byTooltip('Edit this event'), findsOneWidget);
    });
  });
}
