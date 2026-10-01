import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontline_club_admin/widgets/admin_charts.dart';

Future<void> _pump(WidgetTester tester, Widget child, {ThemeData? theme}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(theme: theme ?? FlcTheme.light(), home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child)))));
  await tester.pumpAndSettle();
}

void main() {
  final List<(DateTime, double)> pts = <(DateTime, double)>[for (int i = 0; i < 20; i++) (DateTime(2026, 9, 1 + i), (i * 3).toDouble())];

  testWidgets('line chart draws in light and dark without errors', (tester) async {
    await _pump(tester, AdminLineChart(points: pts, format: (double v) => '$v'));
    expect(tester.takeException(), isNull);
    await _pump(tester, AdminLineChart(points: pts, format: (double v) => '$v'), theme: FlcTheme.dark());
    expect(tester.takeException(), isNull);
  });

  testWidgets('bar chart draws, and says so when there is nothing to show', (tester) async {
    await _pump(tester, AdminBarChart(bars: <(String, double)>[for (int i = 0; i < 12; i++) ('M$i', i * 10.0)], format: (double v) => '$v'));
    expect(tester.takeException(), isNull);
    await _pump(tester, AdminBarChart(bars: const <(String, double)>[('a', 0), ('b', 0)], format: (double v) => '$v'));
    expect(find.text('Nothing to show yet.'), findsOneWidget);
  });

  testWidgets('donut lists each slice with its share', (tester) async {
    await _pump(tester, AdminDonut(slices: const <(String, double)>[('Standard', 30), ('Member', 10), ('Concession', 0)], format: (double v) => '${v.round()}'));
    expect(find.textContaining('Standard'), findsOneWidget);
    expect(find.textContaining('75%'), findsOneWidget);
    expect(find.textContaining('Concession'), findsNothing); // zero slices are left out
  });

  testWidgets('fill bar shows value against total', (tester) async {
    await _pump(tester, const FillBar(label: 'Standard', value: 42, of: 70));
    expect(find.text('42 of 70'), findsOneWidget);
  });

  test('niceMax rounds up to a tidy axis top', () {
    expect(niceMax(37), 50);
    expect(niceMax(1130), 2000);
    expect(niceMax(0), 1);
  });
}
