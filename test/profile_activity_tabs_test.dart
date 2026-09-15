import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/widgets/profile_activity_tabs.dart';
import 'package:wing/core/widgets/profile_execution_activity.dart';
import 'package:wing/core/widgets/profile_tool_activity.dart';
import 'package:wing/core/widgets/anchored_expansion_tile.dart';
import 'package:wing/core/utils/expansion_scroll_controller.dart';

void main() {
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('tabs retain details and Thinking at phone scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late StateSetter update;
      var completed = 1;
      var showTasks = true;
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ProfileActivitySection(
                      initiallyExpanded: true,
                      toolCount: 5,
                      tabs: [
                        if (showTasks)
                          ProfileActivityTab(
                            id: 'tasks',
                            label: 'Tasks $completed/4',
                            child: const Text('Task details'),
                          ),
                        ProfileActivityTab(
                          id: 'agents',
                          label: 'Agents 1/2',
                          child: const Text('Agent details'),
                          onSelected: () => activations++,
                        ),
                      ],
                      thinking: const ProfileReasoningDisclosure(
                        text: 'Reasoning details',
                        running: true,
                      ),
                      children: const [
                        ProfileToolActivity(
                          messages: [
                            {
                              'id': 1,
                              'role': 'tool',
                              'tool_name': 'skill_view',
                              'content': 'Saved tool detail',
                            },
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('skill_view'));
      await tester.pumpAndSettle();
      expect(find.text('Saved tool detail'), findsOneWidget);
      await tester.tap(find.text('Tasks 1/4'));
      await tester.pumpAndSettle();
      expect(find.text('Task details'), findsOneWidget);
      expect(find.text('Saved tool detail'), findsNothing);
      expect(find.text('Thinking'), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('activity-thinking-divider')))
            .dy,
        lessThan(tester.getTopLeft(find.text('Thinking')).dy),
      );
      update(() => completed = 2);
      await tester.pumpAndSettle();
      expect(find.text('Task details'), findsOneWidget);
      await tester.tap(find.text('Agents 1/2'));
      await tester.pumpAndSettle();
      expect(activations, 1);
      expect(find.text('Agent details'), findsOneWidget);
      await tester.tap(find.text('Thinking'));
      await tester.pumpAndSettle();
      expect(find.text('Reasoning details'), findsOneWidget);
      await tester.tap(find.text('Tools 5'));
      await tester.pumpAndSettle();
      expect(find.text('Saved tool detail'), findsOneWidget);
      expect(find.text('Reasoning details'), findsOneWidget);
      await tester.tap(find.text('Tasks 2/4'));
      await tester.pumpAndSettle();
      update(() => showTasks = false);
      await tester.pumpAndSettle();
      expect(find.text('Saved tool detail'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'switching category preserves its position in reversed transcript',
    (tester) async {
      final scroll = ExpansionScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationListener<ExpansionAnchorNotification>(
              onNotification: (event) {
                scroll.anchorExpansion(event.anchor);
                return true;
              },
              child: ListView(
                reverse: true,
                controller: scroll,
                children: [
                  const SizedBox(height: 40),
                  ProfileActivityTabs(
                    tabs: [
                      ProfileActivityTab(
                        id: 'tools',
                        label: 'Tools',
                        child: const SizedBox(height: 60),
                      ),
                      ProfileActivityTab(
                        id: 'tasks',
                        label: 'Tasks',
                        child: const SizedBox(height: 300),
                      ),
                    ],
                  ),
                  const SizedBox(height: 700),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.text('Tasks')).dy;
      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Tasks')).dy, closeTo(before, 1));
      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Tasks')).dy, closeTo(before, 1));
      expect(tester.takeException(), isNull);
    },
  );
}
