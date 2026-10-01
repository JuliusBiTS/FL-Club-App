import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontline_club_app/features/loyalty/loyalty_widgets.dart';

Future<void> _pump(WidgetTester tester, Widget child, {ThemeData? theme}) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(theme: theme ?? FlcTheme.light(), home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('punch card shows progress, one stamp per event so far, and a gift at the end', (tester) async {
    await _pump(tester, const PunchCard(balance: 4, threshold: 10));
    expect(find.text('4 of 10'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(4));
    expect(find.byIcon(Icons.card_giftcard), findsOneWidget);
    expect(find.textContaining('6 more events'), findsOneWidget);
  });

  testWidgets('punch card wording changes for the last stamp, none yet, and a waiting reward', (tester) async {
    await _pump(tester, const PunchCard(balance: 9, threshold: 10));
    expect(find.textContaining('One more event'), findsOneWidget);

    await _pump(tester, const PunchCard(balance: 0, threshold: 10));
    expect(find.textContaining('starts with your next event'), findsOneWidget);

    await _pump(tester, const PunchCard(balance: 0, threshold: 10, rewardsReady: 1));
    expect(find.text('Free ticket ready'), findsOneWidget);
  });

  testWidgets('works with other thresholds and in dark mode', (tester) async {
    await _pump(tester, const PunchCard(balance: 2, threshold: 6), theme: FlcTheme.dark());
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reward ticket says free ticket and when to use it by', (tester) async {
    await _pump(tester, RewardTicket(earnedAt: DateTime(2026, 9, 1), expiresAt: DateTime(2027, 3, 4)));
    expect(find.text('Free ticket'), findsOneWidget);
    expect(find.text('Use by 4 Mar 2027'), findsOneWidget);

    await _pump(tester, RewardTicket(earnedAt: DateTime(2026, 9, 1)));
    expect(find.text('No expiry'), findsOneWidget);
  });
}
