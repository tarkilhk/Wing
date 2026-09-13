import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/widgets/activity_shimmer.dart';

void main() {
  testWidgets('motion stops when disabled, hidden or idle and can resume', (
    tester,
  ) async {
    Future<void> show({
      bool active = true,
      bool reducedMotion = false,
      bool visible = true,
    }) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: TickerMode(
            enabled: visible,
            child: Scaffold(
              body: ActivityShimmer(
                active: active,
                child: const Text('Checking sources…'),
              ),
            ),
          ),
        ),
      ),
    );

    await show();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isTrue);
    for (final state in ['reduced', 'hidden', 'idle']) {
      await show(
        reducedMotion: state == 'reduced',
        visible: state != 'hidden',
        active: state != 'idle',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.text('Checking sources…'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await show();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ShaderMask), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
