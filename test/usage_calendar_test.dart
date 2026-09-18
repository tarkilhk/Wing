import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/usage_analytics.dart';
import 'package:wing/core/screens/administration/usage_charts.dart';
import 'package:wing/core/theme/wing_theme.dart';

void main() {
  testWidgets(
    'day tooltips replace each other and distinguish zero from unknown',
    (tester) async {
      final daily = UsageDaily.fromJson(
        {
          'daily': [
            {'day': '2026-09-18', 'input_tokens': 10, 'output_tokens': 20},
          ],
        },
        period: 365,
        loadedAt: DateTime.utc(2026, 9, 18),
      );
      final selected = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: Scaffold(
            body: UsageCalendar(
              daily: daily,
              rangeStart: daily.days.first.date,
              rangeEnd: daily.days.last.date,
              selected: null,
              onSelected: (day) => selected.add(day.id),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('usage-day-2026-09-17')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('0 tokens', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('usage-day-2026-09-18')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Tokens unavailable', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('0 tokens', findRichText: true), findsNothing);
      expect(selected, ['2026-09-17', '2026-09-18']);
      await tester.tapAt(const Offset(300, 300));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Tokens unavailable', findRichText: true),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  // Preserve the partial UTC boundary and every weekday alignment in both bands.
  for (var weekday = 0; weekday < 7; weekday++) {
    testWidgets('full year stays fixed across ranges, weekday $weekday', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final daily = UsageDaily.fromJson(
        {'daily': <dynamic>[]},
        period: 365,
        loadedAt: DateTime.utc(2026, 9, 13 + weekday),
      );
      var width = 358.0, period = 7;
      UsageDay? selected;
      Future<void> show() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(Brightness.dark),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: UsageCalendar(
                    daily: daily,
                    rangeStart: daily.days.last.date.subtract(
                      Duration(days: period),
                    ),
                    rangeEnd: daily.days.last.date,
                    selected: selected?.id,
                    onSelected: (day) => selected = day,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Finder day(String id) => find.byKey(ValueKey('usage-day-$id'));
      await show();
      expect(find.byTooltip('Earlier dates'), findsNothing);
      expect(find.byTooltip('Later dates'), findsNothing);
      expect(daily.days.length, 366);
      final samples = [daily.days.first, daily.days[180], daily.days.last];
      expect(tester.widgetList<InkWell>(find.byType(InkWell)).length, 366);
      final bounds = {for (final d in samples) d.id: tester.getRect(day(d.id))};
      for (final range in usagePeriods) {
        period = range;
        await show();
        for (final d in samples) {
          expect(tester.getRect(day(d.id)), bounds[d.id]);
        }
      }
      for (final nextWidth in [288.0, 900.0]) {
        width = nextWidth;
        await show();
        final grid = find.byKey(const ValueKey('usage-activity-grid'));
        expect(tester.getSize(grid).width, closeTo(width, .01));
        for (final d in samples) {
          final rect = tester.getRect(day(d.id));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width + .01));
        }
        await tester.tap(day(daily.days.first.id));
        expect(selected?.id, daily.days.first.id);
        await tester.tap(day(daily.days.last.id));
        expect(selected?.id, daily.days.last.id);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
