import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/models/gateway_todo.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/profile_execution_activity.dart';
import 'package:hermes_android/core/widgets/profile_subagent_panel.dart';
import 'package:hermes_android/core/widgets/profile_tool_activity.dart';
import 'package:hermes_android/core/widgets/profile_transcript_disclosure.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_actions_fixture.dart';

void main() {
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('nested activity headers fit a phone at text scale $scale', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final fixture = ProfileActionsFixture();
      final controller = ProfileWorkspaceController(
        connection: identityTestConnection(),
        connectionIdentity: 'compact-details',
        preferences: await SharedPreferences.getInstance(),
        gatewayFactory: fixture.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final chat = await controller.createChat();
      chat.subagents = [
        GatewaySubagentActivity.fromGatewayEvent('subagent.start', {
          'subagent_id': 'one',
          'goal': 'Compare the available stays',
        })!,
        GatewaySubagentActivity.fromGatewayEvent('subagent.complete', {
          'subagent_id': 'two',
          'goal': 'Check privacy',
          'status': 'completed',
        })!,
      ];
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: hermesTheme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ProfileActivitySection(
                  initiallyExpanded: true,
                  children: [
                    const ProfileTodoPanel(
                      todos: [
                        GatewayTodo(
                          id: 'one',
                          content:
                              'Check the full list of available properties and compare privacy.',
                          status: GatewayTodoStatus.completed,
                        ),
                        GatewayTodo(
                          id: 'two',
                          content: 'Review alternatives',
                          status: GatewayTodoStatus.pending,
                        ),
                      ],
                    ),
                    ProfileSubagentPanel(controller: controller, chat: chat),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 active · 2 total'), findsOneWidget);
      if (scale == 1) {
        expect(
          tester.getSize(find.byType(ProfileActivitySection)).height,
          lessThanOrEqualTo(100),
        );
        expect(
          tester.getTopLeft(find.text('Tasks 1/2')).dx,
          tester.getTopLeft(find.text('Subagents')).dx,
        );
      }
      await tester.tap(find.text('Tasks 1/2'));
      await tester.pumpAndSettle();
      expect(find.text('Review alternatives'), findsOneWidget);
      await tester.tap(find.text('Tasks 1/2'));
      await tester.pumpAndSettle();
      expect(find.text('Review alternatives'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loading keeps header alignment and expansion callbacks work', (
    tester,
  ) async {
    final changes = <bool>[];
    var loading = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ProfileTranscriptDisclosure(
                label: 'Subagents',
                icon: Icons.account_tree_outlined,
                loading: loading,
                summary: const Text('1 active'),
                onExpansionChanged: changes.add,
                children: const [Text('Agent details')],
              );
            },
          ),
        ),
      ),
    );
    final before = tester.getTopLeft(find.text('Subagents'));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    update(() => loading = false);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Subagents')), before);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Subagents'));
    await tester.pumpAndSettle();
    expect(find.text('Agent details'), findsOneWidget);
    await tester.tap(find.text('Subagents'));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    expect(find.text('Agent details'), findsNothing);
  });
}
