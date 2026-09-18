import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/usage_analytics.dart';
import 'package:wing/core/screens/administration/usage_charts.dart';
import 'package:wing/core/theme/wing_theme.dart';

void main() {
  // Exercise every possible weekday at both ends of the rolling year.
  for (var weekday = 0; weekday < 7; weekday++) {
    testWidgets(
      'responsive year paging preserves all dates, weekday $weekday',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final daily = UsageDaily.fromJson(
          {'daily': <dynamic>[]},
          period: 365,
          loadedAt: DateTime.utc(2026, 9, 13 + weekday),
        );
        double width = 358;
        UsageDay? selected;
        Future<void> show() => tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(Brightness.dark),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: UsageCalendar(
                    daily: daily,
                    selected: selected?.id,
                    onSelected: (day) => selected = day,
                  ),
                ),
              ),
            ),
          ),
        );
        List<String> visible() =>
            tester
                .widgetList<InkWell>(find.byType(InkWell))
                .map((w) => w.key)
                .whereType<ValueKey<String>>()
                .map((key) => key.value)
                .where((value) => value.startsWith('usage-day-'))
                .map((value) => value.substring('usage-day-'.length))
                .toList()
              ..sort();
        bool enabled(String tooltip) =>
            tester
                .widget<IconButton>(
                  find.widgetWithIcon(
                    IconButton,
                    tooltip == 'Earlier dates'
                        ? Icons.chevron_left
                        : Icons.chevron_right,
                  ),
                )
                .onPressed !=
            null;
        Future<void> page(String tooltip) async {
          await tester.tap(find.byTooltip(tooltip));
          await tester.pumpAndSettle();
        }

        await show();
        final grid = find.byKey(const ValueKey('usage-activity-grid'));
        expect(tester.getSize(grid).width, closeTo(width, .01));
        final latest = visible();
        expect(latest.length, greaterThan(150));
        expect(latest.last, daily.days.last.id);
        expect(enabled('Later dates'), isFalse);
        final visited = <String>{};
        while (true) {
          final dates = visible();
          expect(visited.intersection(dates.toSet()), isEmpty);
          visited.addAll(dates);
          if (!enabled('Earlier dates')) break;
          await page('Earlier dates');
        }
        expect(visited, daily.days.map((day) => day.id).toSet());
        while (enabled('Later dates')) {
          await page('Later dates');
        }
        expect(visible(), latest);

        await page('Earlier dates');
        final lastBeforeResize = visible().last;
        width = 288;
        await show();
        expect(visible().last, lastBeforeResize);
        expect(tester.getSize(grid).width, closeTo(width, .01));
        final chosen = visible().first;
        await tester.tap(find.byKey(ValueKey('usage-day-$chosen')));
        expect(selected?.id, chosen);
        // Widen enough to fit the year. Navigation back to today must survive.
        width = 900;
        await show();
        expect(visible().last, lastBeforeResize);
        expect(enabled('Later dates'), isTrue);
        await page('Later dates');
        expect(visible(), daily.days.map((day) => day.id).toList());
        expect(find.byTooltip('Earlier dates'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
