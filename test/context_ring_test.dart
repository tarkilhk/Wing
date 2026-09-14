import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/models/context_occupancy.dart';
import 'package:hermes_android/core/widgets/context_ring.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';

void main() {
  test('parses and clamps server occupancy', () {
    final value = ContextOccupancy.fromJson({
      'context_used': 1200,
      'context_max': 1000,
      'context_percent': 125.5,
      'context_estimated': true,
    });
    expect(value, isNotNull);
    expect(value!.used, 1200);
    expect(value.max, 1000);
    expect(value.percent, 100);
    expect(value.estimated, isTrue);
  });

  test('returns unknown for missing, zero, or nonfinite server values', () {
    expect(ContextOccupancy.fromJson(null), isNull);
    expect(
      ContextOccupancy.fromJson({
        'context_used': 1,
        'context_max': 0,
        'context_percent': 1,
      }),
      isNull,
    );
    expect(
      ContextOccupancy.fromJson({
        'context_used': 1,
        'context_max': 10,
        'context_percent': double.nan,
      }),
      isNull,
    );
  });

  testWidgets('unknown context is static, accessible and never reports zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: ContextRing())),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Context usage unknown'), findsOneWidget);
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('context-ring-paint')),
    );
    expect((paint.painter! as ContextRingPainter).progress, isNull);
    await tester.tap(find.byKey(const ValueKey('context-ring-details')));
    await tester.pumpAndSettle();
    expect(find.text('Context usage unknown'), findsOneWidget);
    expect(find.textContaining('0 percent'), findsNothing);
  });

  testWidgets('tap reveals exact server usage and its estimate qualifier', (
    tester,
  ) async {
    const occupancy = ContextOccupancy(
      used: 800,
      max: 1000,
      percent: 80,
      estimated: true,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: ContextRing(occupancy: occupancy)),
        ),
      ),
    );
    expect(
      find.bySemanticsLabel(
        'Approximately 800 of 1000 tokens, 80 percent used',
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('context-ring-paint'))),
      const Size.square(18),
    );
    await tester.tap(find.byKey(const ValueKey('context-ring-details')));
    await tester.pumpAndSettle();
    expect(
      find.text('Approximately 800 of 1000 tokens, 80 percent used'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'occupancy keeps the existing warning thresholds in both themes',
    (tester) async {
      for (final brightness in Brightness.values) {
        final tokens = HermesTokens.forBrightness(brightness);
        for (final percent in [0.0, 64.9, 65.0, 84.9, 85.0, 100.0]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: hermesTheme(brightness),
              home: Scaffold(
                body: Center(
                  child: ContextRing(
                    occupancy: ContextOccupancy(
                      used: percent.round(),
                      max: 100,
                      percent: percent,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final painter =
              tester
                      .widget<CustomPaint>(
                        find.byKey(const ValueKey('context-ring-paint')),
                      )
                      .painter!
                  as ContextRingPainter;
          expect(painter.progress, percent / 100);
          expect(
            painter.color,
            percent >= 85
                ? tokens.danger
                : percent >= 65
                ? tokens.warning
                : tokens.accent,
          );
        }
      }
    },
  );
}
