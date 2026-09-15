import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/models/context_occupancy.dart';
import 'package:hermes_android/core/widgets/context_ring.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';

void main() {
  testWidgets('context details can be reached and opened with a keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hermesTheme(Brightness.light),
        home: const Scaffold(body: Center(child: ContextRing(occupancy: null))),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('context-ring-details')),
    );
    expect(button.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('context-usage-popover')), findsOneWidget);
  });

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
    expect(find.text('≈ 800 / 1,000 tokens'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byKey(const ValueKey('context-ring-details')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('context-usage-popover')), findsNothing);
  });

  testWidgets(
    'context popover stays anchored without dismissing the keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(412, 823);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.reset);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: hermesTheme(Brightness.dark),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(focusNode: focus),
                  const Row(
                    children: [
                      SizedBox(width: 60),
                      ContextRing(
                        occupancy: ContextOccupancy(
                          used: 94090,
                          max: 272000,
                          percent: 35,
                          estimated: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.showKeyboard(find.byType(TextField));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(find.byKey(const ValueKey('context-ring-details')));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('context-usage-popover'));
      final ring = tester.getRect(
        find.byKey(const ValueKey('context-ring-paint')),
      );
      final bounds = tester.getRect(card);
      expect(bounds.left, closeTo(ring.left, .1));
      expect(bounds.bottom, closeTo(ring.top - 8, .1));
      expect(bounds.width, lessThanOrEqualTo(260));
      expect(bounds.height, lessThan(120));
      expect(find.byType(AlertDialog), findsNothing);
      expect(focus.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(find.text('≈ 94,090 / 272,000 tokens'));
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(focus.hasFocus, isTrue);
      await tester.tapAt(
        tester.getTopLeft(find.byType(TextField)) + const Offset(8, 8),
      );
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      expect(focus.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

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
