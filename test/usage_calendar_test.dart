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

  // Every UTC boundary remains reachable through the single band.
  for (var weekday = 0; weekday < 7; weekday++) {
    testWidgets(
      'single band pages through year and keeps range geometry, weekday $weekday',
      (tester) async {
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
        List<String> visible() =>
            tester
                .widgetList<InkWell>(find.byType(InkWell))
                .map((w) => w.key)
                .whereType<ValueKey<String>>()
                .map((key) => key.value)
                .where((key) => key.startsWith('usage-day-'))
                .map((key) => key.substring('usage-day-'.length))
                .toList()
              ..sort();
        bool enabled(String tooltip) =>
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == tooltip,
                  ),
                )
                .onPressed !=
            null;
        Future<void> page(String tooltip) async {
          await tester.tap(find.byTooltip(tooltip));
          await tester.pumpAndSettle();
        }

        expect(find.byKey(const ValueKey('usage-year-band')), findsOneWidget);
        expect(enabled('Earlier dates'), isTrue);
        expect(enabled('Later dates'), isFalse);
        final latest = visible();
        expect(latest.length, lessThan(366));
        expect(latest.last, daily.days.last.id);
        final samples = [latest.first, latest.last];
        final bounds = {for (final id in samples) id: tester.getRect(day(id))};
        for (final range in usagePeriods) {
          period = range;
          await show();
          expect(visible(), latest);
          for (final id in samples) {
            expect(tester.getRect(day(id)), bounds[id]);
          }
        }
        final visited = latest.toSet();
        while (enabled('Earlier dates')) {
          await page('Earlier dates');
          visited.addAll(visible());
        }
        expect(visited, daily.days.map((d) => d.id).toSet());
        final oldest = visible().first;
        final lastBeforeResize = visible().last;
        await tester.tap(day(oldest));
        expect(selected?.id, oldest);
        width = 288;
        await show();
        expect(visible().last, lastBeforeResize);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('usage-activity-grid')))
              .width,
          closeTo(width, .01),
        );
        while (enabled('Later dates')) {
          await page('Later dates');
        }
        expect(visible().last, daily.days.last.id);
        width = 900;
        await show();
        expect(visible(), daily.days.map((d) => d.id).toList());
        expect(find.byTooltip('Earlier dates'), findsNothing);
        expect(find.byKey(const ValueKey('usage-year-band')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
