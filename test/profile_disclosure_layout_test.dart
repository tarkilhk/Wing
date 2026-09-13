import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/theme/profile_workspace_theme.dart';
import 'package:hermes_android/core/widgets/profile_execution_activity.dart';
import 'package:hermes_android/core/widgets/profile_tool_activity.dart';

void main() {
  const activityKey = ValueKey('saved-activity');
  const thoughtKey = ValueKey('saved-thought');

  Future<void> show(WidgetTester tester, double scale) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: profileWorkspaceTheme(hermesTheme(Brightness.dark)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProfileToolActivitySection(
                  key: activityKey,
                  groups: [
                    [
                      {'role': 'tool', 'content': 'First result'},
                      {'role': 'tool', 'content': 'Second result'},
                    ],
                  ],
                ),
                const ProfileReasoningDisclosure(
                  key: thoughtKey,
                  text: 'Checked the available options.',
                ),
                const Text('The follow-up is running.'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('collapsed disclosures leave room for the answer on a phone', (
    tester,
  ) async {
    await show(tester, 1);
    final activity = tester.getRect(find.byKey(activityKey));
    final thought = tester.getRect(find.byKey(thoughtKey));
    expect(activity.height, greaterThanOrEqualTo(28));
    expect(thought.height, greaterThanOrEqualTo(28));
    expect(thought.bottom - activity.top, lessThanOrEqualTo(60));
    expect(thought.top, closeTo(activity.bottom, 0.1));
    expect(
      tester.getCenter(find.text('2 tool calls')).dy,
      closeTo(tester.getCenter(find.text('Activity')).dy, 0.1),
    );
    expect(
      tester.getTopLeft(find.text('Activity')).dx,
      tester.getTopLeft(find.text('Thought')).dx,
    );
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('disclosures remain readable and expandable at scale $scale', (
      tester,
    ) async {
      await show(tester, scale);
      expect(find.text('2 tool calls'), findsOneWidget);
      expect(find.text('First result'), findsNothing);
      expect(find.text('Checked the available options.'), findsNothing);
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 tool results'));
      await tester.pumpAndSettle();
      expect(find.text('First result'), findsOneWidget);
      expect(find.text('Second result'), findsOneWidget);
      await tester.ensureVisible(find.text('Thought'));
      await tester.tap(find.text('Thought'));
      await tester.pumpAndSettle();
      expect(find.text('Checked the available options.'), findsOneWidget);
      await tester.tap(find.text('Thought'));
      await tester.pumpAndSettle();
      expect(find.text('Checked the available options.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
