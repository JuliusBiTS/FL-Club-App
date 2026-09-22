import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One client for the whole file, created OUTSIDE any test's fake clock (its
/// auth layer starts a periodic refresh timer that fake-async would flag).
/// It is never used to make a request.
late SupabaseClient _sharedClient;

/// A repository that never touches the network: it serves canned data and
/// records what the editor asked it to save.
class FakeEventRepo extends EventAdminRepository {
  FakeEventRepo({this.draft, this.events = const <EventModel>[]}) : super(_sharedClient);

  final EventDraft? draft;
  final List<EventModel> events;

  final List<String> savedStatuses = <String>[];
  final List<EventDraft> savedDrafts = <EventDraft>[];

  @override
  Future<List<TicketTypeDraft>> defaultTicketTemplate() async => <TicketTypeDraft>[
        TicketTypeDraft(name: 'Standard', priceMinor: 1500),
        TicketTypeDraft(name: 'Member', audience: 'member', requiresMember: true, priceMinor: 500),
        TicketTypeDraft(name: 'Concession', audience: 'concession', priceMinor: 800, requiresProof: true),
      ];

  @override
  Future<EventDraft> loadDraft(String eventId) async => draft!;

  @override
  Future<List<EventModel>> listEvents() async => events;

  @override
  Future<Set<String>> sellingFastIds() async => <String>{'e2'};

  @override
  Future<String> save(EventDraft draft, {required String status}) async {
    savedStatuses.add(status);
    savedDrafts.add(draft);
    return draft.id ?? 'new-id';
  }

  @override
  Future<List<Map<String, dynamic>>> pushCampaigns({String? eventId, int limit = 20}) async => <Map<String, dynamic>>[];
}

/// A text field whose current value is exactly [value] (hint text stays in the
/// tree at zero opacity, so find.text would over-match).
Finder _fieldWithValue(String value) =>
    find.byWidgetPredicate((Widget w) => w is EditableText && w.controller.text == value);

Future<void> _pumpEditor(
  WidgetTester tester, {
  required FakeEventRepo repo,
  bool isAdmin = true,
  String? eventId,
  EventDraft? copyOf,
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlcTheme.light(),
      home: EventEditorScreen(repository: repo, isAdmin: isAdmin, eventId: eventId, copyOf: copyOf),
    ),
  );
  await tester.pumpAndSettle();
}

EventDraft _liveDraft() => EventDraft(
      id: 'e1',
      status: 'published',
      title: 'Afghanistan 2026',
      summary: 'An updated look at power and exile.',
      category: 'Panel discussion',
      startsAt: DateTime(2027, 9, 9, 19),
      capacityTotal: 120,
      capacityApp: 100,
      capacityEventbrite: 20,
      issuedTickets: 40,
      ticketTypes: <TicketTypeDraft>[
        TicketTypeDraft(id: 't1', name: 'Standard', priceMinor: 1500, quantity: 60, sold: 30),
        TicketTypeDraft(id: 't2', name: 'Member', audience: 'member', requiresMember: true, priceMinor: 500, quantity: 40, sold: 10),
      ],
    );

void main() {
  setUpAll(() {
    _sharedClient = SupabaseClient('http://localhost:54321', 'anon-key');
    _sharedClient.auth.stopAutoRefresh();
  });
  tearDownAll(() => _sharedClient.dispose());

  testWidgets('typing a title updates the live preview', (WidgetTester tester) async {
    await _pumpEditor(tester, repo: FakeEventRepo());

    expect(find.text('Your event title'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Title *'), 'Book talk: Betrayal');
    await tester.pump();

    expect(find.text('Book talk: Betrayal'), findsWidgets); // app bar + preview card
    expect(find.text('Your event title'), findsNothing);
  });

  testWidgets('"Use the club\'s standard tickets" fills in the three template rows', (WidgetTester tester) async {
    await _pumpEditor(tester, repo: FakeEventRepo());
    await tester.scrollUntilVisible(find.text('Use the club\'s standard tickets'), 600, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Use the club\'s standard tickets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use the club\'s standard tickets'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(_fieldWithValue('Standard'), findsOneWidget);
    expect(_fieldWithValue('Member'), findsOneWidget);
    expect(_fieldWithValue('Concession'), findsOneWidget);
  });

  testWidgets('publishing an empty event lists what to fix and saves nothing', (WidgetTester tester) async {
    final FakeEventRepo repo = FakeEventRepo();
    await _pumpEditor(tester, repo: repo);

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(find.text('Fix these before publishing'), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('Give the event a title.')), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('Pick a start date and time.')), findsOneWidget);
    expect(repo.savedStatuses, isEmpty);
  });

  testWidgets('publishing a ready event warns about gaps, saves as published, then offers to notify', (WidgetTester tester) async {
    final FakeEventRepo repo = FakeEventRepo();
    await _pumpEditor(
      tester,
      repo: repo,
      copyOf: EventDraft(title: 'Screening + Q&A: Life Support', startsAt: DateTime(2027, 9, 24, 19), capacityTotal: 80, capacityApp: 80),
    );

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(find.text('Publish anyway?'), findsOneWidget); // no picture / summary / category…

    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Publish')));
    await tester.pumpAndSettle();

    expect(repo.savedStatuses, <String>['published']);
    expect(find.text('Tell people about it?'), findsOneWidget);
  });

  testWidgets('staff on a live event see price and capacity locked', (WidgetTester tester) async {
    await _pumpEditor(tester, repo: FakeEventRepo(draft: _liveDraft()), eventId: 'e1', isAdmin: false);
    await tester.scrollUntilVisible(find.textContaining('price and capacity are locked'), 400, scrollable: find.byType(Scrollable).first);

    expect(find.textContaining('price and capacity are locked'), findsOneWidget);
    final TextField capacity = tester.widget<TextField>(find.descendant(of: find.widgetWithText(TextFormField, 'Total capacity'), matching: find.byType(TextField)));
    expect(capacity.enabled, isFalse);
  });

  testWidgets('admins can edit price and capacity on a live event', (WidgetTester tester) async {
    await _pumpEditor(tester, repo: FakeEventRepo(draft: _liveDraft()), eventId: 'e1');
    await tester.scrollUntilVisible(find.widgetWithText(TextFormField, 'Total capacity'), 400, scrollable: find.byType(Scrollable).first);

    expect(find.textContaining('price and capacity are locked'), findsNothing);
    final TextField capacity = tester.widget<TextField>(find.descendant(of: find.widgetWithText(TextFormField, 'Total capacity'), matching: find.byType(TextField)));
    expect(capacity.enabled, isTrue);
  });

  testWidgets('a live event with sales can\'t have a ticket type deleted, only withdrawn', (WidgetTester tester) async {
    await _pumpEditor(tester, repo: FakeEventRepo(draft: _liveDraft()), eventId: 'e1');
    await tester.scrollUntilVisible(find.text('30 sold'), 400, scrollable: find.byType(Scrollable).first);

    expect(find.text('30 sold'), findsOneWidget);
    expect(find.byTooltip('Remove ticket type'), findsNothing);
  });

  testWidgets('choosing FC Recommends and a perk shows both on the preview card', (WidgetTester tester) async {
    await _pumpEditor(tester, repo: FakeEventRepo(), copyOf: EventDraft(title: 'World Briefing', startsAt: DateTime(2027, 1, 1, 19)));
    await tester.scrollUntilVisible(find.text('FC Recommends'), 500, scrollable: find.byType(Scrollable).first);

    await tester.tap(find.widgetWithText(ChoiceChip, 'FC Recommends'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, 'Free drink with your ticket'));
    await tester.pump();

    // One chip on the picker, one badge on the preview card.
    expect(find.text('FC Recommends'), findsNWidgets(2));
    expect(find.text('Free drink with your ticket'), findsWidgets);
  });

  testWidgets('manager lists events, filters and flags "selling fast"', (WidgetTester tester) async {
    final DateTime soon = DateTime.now().toUtc().add(const Duration(days: 5));
    final List<EventModel> events = <EventModel>[
      EventModel(id: 'e1', slug: 'a', title: 'Draft event', startsAt: soon, status: 'draft'),
      EventModel(id: 'e2', slug: 'b', title: 'Live event', startsAt: soon, status: 'published'),
      EventModel(id: 'e3', slug: 'c', title: 'Old event', startsAt: DateTime.now().toUtc().subtract(const Duration(days: 30)), status: 'published'),
    ];
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(theme: FlcTheme.light(), home: EventsManagerScreen(repository: FakeEventRepo(events: events), isAdmin: true)));
    await tester.pumpAndSettle();

    expect(find.text('Draft event'), findsOneWidget);
    expect(find.text('Live event'), findsOneWidget);
    expect(find.text('Old event'), findsNothing); // "Upcoming" filter hides past events
    expect(find.text('Selling fast'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Past'));
    await tester.pumpAndSettle();
    expect(find.text('Old event'), findsOneWidget);
    expect(find.text('Live event'), findsNothing);
  });
}
