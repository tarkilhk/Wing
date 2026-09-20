import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/chat_working_border.dart';

void main() {
  testWidgets(
    'motion preference stops ticks and row actions remain reachable',
    (tester) async {
      var taps = 0;
      var actions = 0;
      var longPresses = 0;
      Future<void> show({bool reduced = false, bool working = true}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(Brightness.dark),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: ChatWorkingBorder(
                  working: working,
                  child: ListTile(
                    title: const Text('Working chat'),
                    onTap: () => taps++,
                    onLongPress: () => longPresses++,
                    trailing: IconButton(
                      icon: const Icon(Icons.more_horiz),
                      onPressed: () => actions++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }

      await show();
      final bounds = tester.getRect(find.byType(ListTile));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.tap(find.text('Working chat'));
      await tester.tap(find.byType(IconButton));
      await tester.longPress(find.text('Working chat'));
      expect((taps, actions, longPresses), (1, 1, 1));

      await show(reduced: true);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.getRect(find.byType(ListTile)), bounds);
      expect(
        find.descendant(
          of: find.descendant(
            of: find.byType(ChatWorkingBorder),
            matching: find.byType(IgnorePointer),
          ),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );

      await show();
      expect(tester.binding.hasScheduledFrame, isTrue);
      await show(working: false);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.getRect(find.byType(ListTile)), bounds);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
