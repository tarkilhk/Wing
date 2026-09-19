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
      'single band scrolls through year and keeps range geometry, weekday $weekday',
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
        final band = find.byKey(const ValueKey('usage-year-band'));
        final scroll = find.byKey(const ValueKey('usage-calendar-scroll'));
        ScrollPosition position() => tester
            .state<ScrollableState>(
              find.descendant(of: scroll, matching: find.byType(Scrollable)),
            )
            .position;
        List<String> visible() {
          final viewport = tester.getRect(band);
          return find
              .byType(InkWell)
              .evaluate()
              .where((element) {
                final box = element.renderObject! as RenderBox;
                final center = box.localToGlobal(box.size.center(Offset.zero));
                return center.dx >= viewport.left &&
                    center.dx <= viewport.right;
              })
              .map(
                (element) => (element.widget.key! as ValueKey<String>).value
                    .substring('usage-day-'.length),
              )
              .toList()
            ..sort();
        }

        Future<void> drag(double dx) async {
          await tester.drag(band, Offset(dx, 0));
          await tester.pumpAndSettle();
        }

        expect(band, findsOneWidget);
        expect(find.byTooltip('Earlier dates'), findsNothing);
        expect(find.byTooltip('Later dates'), findsNothing);
        expect(position().pixels, 0);
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
        String label() => tester
            .widget<Text>(find.byKey(const ValueKey('usage-visible-dates')))
            .data!;
        final latestLabel = label();
        final gesture = await tester.startGesture(tester.getCenter(band));
        await gesture.moveBy(const Offset(25, 0));
        await gesture.moveBy(const Offset(60, 0));
        await tester.pump();
        expect(position().pixels, greaterThan(0));
        expect(label(), isNot(latestLabel));
        expect(selected, isNull);
        await gesture.moveBy(const Offset(-35, 0));
        await tester.pump();
        expect(label(), isNot(latestLabel));
        await gesture.up();
        await tester.pumpAndSettle();
        await drag(-400);
        expect(label(), latestLabel);
        if (weekday == 0) {
          await tester.tap(day(daily.days.last.id));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('0 tokens', findRichText: true),
            findsOneWidget,
          );
          await tester.fling(band, const Offset(70, 0), 700);
          await tester.pump();
          final releasedAt = position().pixels;
          final releasedLabel = label();
          await tester.pump(const Duration(milliseconds: 100));
          expect(position().pixels, greaterThan(releasedAt));
          expect(label(), isNot(releasedLabel));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('0 tokens', findRichText: true),
            findsNothing,
          );
          await drag(-1000);
        }
        final visited = latest.toSet();
        while (position().pixels < position().maxScrollExtent) {
          await drag(200);
          visited.addAll(visible());
        }
        expect(visited, daily.days.map((d) => d.id).toSet());
        final oldest = visible().first;
        await tester.tap(day(oldest));
        expect(selected?.id, oldest);
        width = 288;
        await show();
        expect(
          position().pixels,
          inInclusiveRange(0, position().maxScrollExtent),
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey('usage-activity-grid')))
              .width,
          closeTo(width, .01),
        );
        while (position().pixels > 0) {
          await drag(-200);
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
