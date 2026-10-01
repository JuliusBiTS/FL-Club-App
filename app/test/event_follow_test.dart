import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontline_club_app/core/auth/profile_provider.dart';
import 'package:frontline_club_app/core/supabase/supabase_providers.dart';
import 'package:frontline_club_app/features/events/data/event_follow_repository.dart';
import 'package:frontline_club_app/features/events/events_providers.dart';
import 'package:frontline_club_app/features/events/presentation/event_detail_screen.dart';
import 'package:frontline_club_app/features/events/presentation/events_feed_controller.dart';
import 'package:frontline_club_app/features/events/presentation/events_feed_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stands in for the database: remembers what was saved/reminded/joined.
class _FakeFollowRepo implements EventFollowRepository {
  _FakeFollowRepo({Set<String> saved = const <String>{}, Set<String> notify = const <String>{}, bool onList = false})
      : saved = <String>{...saved},
        notify = <String>{...notify},
        _onList = onList;

  final Set<String> saved;
  final Set<String> notify;
  bool _onList;
  final List<String> guestEmails = <String>[];

  @override
  Future<EventFollows> load() async => EventFollows(saved: <String>{...saved, ...notify}, notify: <String>{...notify});

  @override
  Future<void> setSaved(String eventId, bool isSaved) async {
    if (isSaved) {
      saved.add(eventId);
    } else {
      saved.remove(eventId);
      notify.remove(eventId);
    }
  }

  @override
  Future<void> setNotify(String eventId, bool on) async {
    if (on) {
      saved.add(eventId);
      notify.add(eventId);
    } else {
      notify.remove(eventId);
    }
  }

  @override
  Future<bool> hasInterest(String eventId) async => _onList;

  @override
  Future<void> registerInterest(String eventId) async => _onList = true;

  @override
  Future<void> registerGuestInterest(String eventId, {required String email, String? name}) async => guestEmails.add(email);

  @override
  Future<void> removeInterest(String eventId) async => _onList = false;
}

class _FakeFeed extends EventsFeedController {
  _FakeFeed(this.events);

  final List<EventModel> events;

  @override
  Future<List<EventModel>> build() async => events;

  @override
  Future<void> refresh() async {}
}

final DateTime _soon = DateTime.now().toUtc().add(const Duration(days: 4));

final EventModel _a = EventModel(id: 'a', slug: 'a', title: 'Afghanistan 2026', startsAt: _soon, status: 'published', category: 'Panel discussion');
final EventModel _b = EventModel(id: 'b', slug: 'b', title: 'Book talk', startsAt: _soon.add(const Duration(days: 2)), status: 'published', category: 'Book talk');

const User _user = User(id: 'u1', appMetadata: <String, dynamic>{}, userMetadata: <String, dynamic>{}, aud: 'authenticated', createdAt: '2026-01-01T00:00:00Z');

List<Override> _common(_FakeFollowRepo repo, {bool signedIn = true, Set<String> soldOut = const <String>{}}) => <Override>[
      currentUserProvider.overrideWithValue(signedIn ? _user : null),
      eventFollowRepositoryProvider.overrideWithValue(repo),
      eventsFeedControllerProvider.overrideWith(() => _FakeFeed(<EventModel>[_a, _b])),
      sellingFastIdsProvider.overrideWith((ref) async => <String>{}),
      soldOutIdsProvider.overrideWith((ref) async => soldOut),
      currentProfileProvider.overrideWith((ref) async => null),
      eventDetailProvider.overrideWith((ref, slug) async => _a),
      ticketTypesProvider.overrideWith((ref, id) async => <TicketTypeModel>[const TicketTypeModel(id: 't1', eventId: 'a', name: 'Standard', priceMinor: 1500, quantity: 50)]),
    ];

Future<void> _pump(WidgetTester tester, Widget home, List<Override> overrides) async {
  tester.view.physicalSize = const Size(420, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(ProviderScope(key: UniqueKey(), overrides: overrides, child: MaterialApp(theme: FlcTheme.light(), home: home)));
  await tester.pumpAndSettle();
}

void main() {
  group('Event page', () {
    testWidgets('offers add-to-calendar and a reminder for an upcoming event', (tester) async {
      await _pump(tester, const EventDetailScreen(slug: 'a'), _common(_FakeFollowRepo()));
      expect(find.text('Add to calendar'), findsOneWidget);
      expect(find.text('Remind me'), findsOneWidget);
      expect(find.byTooltip('Save this event'), findsOneWidget);
    });

    testWidgets('the heart saves the event, and again removes it', (tester) async {
      final repo = _FakeFollowRepo();
      await _pump(tester, const EventDetailScreen(slug: 'a'), _common(repo));

      await tester.tap(find.byTooltip('Save this event'));
      await tester.pumpAndSettle();
      expect(repo.saved, contains('a'));
      expect(find.byTooltip('Remove from saved'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove from saved'));
      await tester.pumpAndSettle();
      expect(repo.saved, isEmpty);
    });

    testWidgets('a sold-out event shows the waiting list; a guest joins with an email', (tester) async {
      final repo = _FakeFollowRepo();
      await _pump(tester, const EventDetailScreen(slug: 'a'), _common(repo, signedIn: false, soldOut: <String>{'a'}));

      expect(find.text('Join the waiting list'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'guest@example.com');
      await tester.tap(find.text('Join the waiting list'));
      await tester.pumpAndSettle();

      expect(repo.guestEmails, <String>['guest@example.com']);
      expect(find.textContaining("You're on the list"), findsOneWidget);
    });

    testWidgets('a signed-in person joins and leaves the waiting list in one tap', (tester) async {
      final repo = _FakeFollowRepo();
      await _pump(tester, const EventDetailScreen(slug: 'a'), _common(repo, soldOut: <String>{'a'}));

      await tester.tap(find.text('Join the waiting list'));
      await tester.pumpAndSettle();
      expect(find.textContaining("You're on the waiting list"), findsOneWidget);

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(find.text('Join the waiting list'), findsOneWidget);
    });

    testWidgets('an event that is not sold out has no waiting list', (tester) async {
      await _pump(tester, const EventDetailScreen(slug: 'a'), _common(_FakeFollowRepo()));
      expect(find.text('Join the waiting list'), findsNothing);
    });
  });

  group('Events feed', () {
    testWidgets('the Saved filter shows only saved events', (tester) async {
      await _pump(tester, const EventsFeedScreen(), _common(_FakeFollowRepo(saved: <String>{'b'})));
      expect(find.text('Afghanistan 2026'), findsOneWidget);
      expect(find.text('Book talk'), findsOneWidget);

      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();

      expect(find.text('Afghanistan 2026'), findsNothing);
      expect(find.text('Book talk'), findsOneWidget);
    });
  });
}
