import 'dart:convert';
import 'dart:ui' show SemanticsAction;

import 'package:wing/core/services/profile_supervision_session.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/gateway_todo.dart';
import 'package:wing/core/models/transcript_message.dart';
import 'package:wing/core/presentation/saved_activity.dart';
import 'package:wing/core/presentation/tool_call_presentation.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/profile_execution_activity.dart';
import 'package:wing/core/widgets/profile_subagent_panel.dart';
import 'package:wing/core/widgets/profile_tool_activity.dart';
import 'package:wing/core/widgets/profile_transcript_disclosure.dart';
import 'package:wing/core/widgets/profile_saved_agents.dart';
import 'package:wing/core/widgets/profile_tool_call.dart';
import 'helpers/pump_markdown_widget.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_actions_fixture.dart';
import 'support/composer_fixture.dart' show emitChatEvent;

void main({Future<void> Function(WidgetTester, String)? capture}) {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('activity rows fit their content in $brightness at $scale', (
        tester,
      ) async {
        if (tester.binding is AutomatedTestWidgetsFlutterBinding) {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
        }
        final calls = [
          for (var index = 0; index < 10; index++)
            ToolCallPresentation.saved(
              TranscriptToolResult.fromRow({
                'id': index,
                'role': 'tool',
                'tool_name': index == 0 ? 'skill_view' : 'browser_exec',
                'args': index == 0
                    ? {'name': 'business-trip-policy-research'}
                    : null,
                'content': index == 2 ? '{"exit_code":1}' : 'Page read',
              }),
            ),
        ];
        const goal =
            'Search native Japanese accommodation websites, apply the '
            'travel dates, compare the cheapest private rooms and save verified '
            'evidence with total prices and cancellation rules.';
        final agents = SavedActivity([
          TranscriptToolResult.fromRow({
            'role': 'tool',
            'tool_name': 'delegate_task',
            'content': jsonEncode({
              'status': 'dispatched',
              'goals': [goal, 'Empty output', 'Read saved findings'],
              'inline_results': [
                {
                  'task_index': 1,
                  'status': 'completed',
                  'summary': '  ',
                  'error': '',
                },
                {
                  'task_index': 2,
                  'status': 'completed',
                  'summary': 'Verified findings',
                },
              ],
            }),
          }),
        ]).agents;
        Future<void> show(Widget child) => tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
          ),
        );
        await show(
          Column(
            children: [
              for (var index = 0; index < calls.length; index++)
                ProfileToolCall(
                  key: ValueKey(('compact-call', index)),
                  call: calls[index],
                ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        for (var index = 0; index < calls.length; index++) {
          final row = find.byKey(ValueKey(('compact-call', index)));
          final text = find.descendant(of: row, matching: find.byType(Text));
          final height = text.evaluate().fold<double>(
            0,
            (sum, element) =>
                sum + tester.getSize(find.byWidget(element.widget)).height,
          );
          expect(tester.getSize(row).height, lessThanOrEqualTo(height + 0.1));
          if (index > 0) {
            expect(
              tester.getRect(row).top,
              closeTo(
                tester
                    .getRect(find.byKey(ValueKey(('compact-call', index - 1))))
                    .bottom,
                0.1,
              ),
            );
          }
        }
        if (capture != null) {
          await capture(tester, 'compact-tools-${brightness.name}-$scale');
        }
        await tester.tap(find.text('Read skill'));
        await tester.pumpAndSettle();
        expect(find.text('Raw details'), findsOneWidget);
        await show(ProfileSavedAgents(agents: agents));
        await tester.pumpAndSettle();
        // Only delivered, nonblank detail gets a disclosure or tap semantics.
        expect(find.byType(ExpansionTile), findsOneWidget);
        expect(find.byIcon(Icons.expand_more), findsOneWidget);
        expect(find.text(goal), findsOneWidget);
        final semantics = tester.ensureSemantics();
        expect(
          tester
              .getSemantics(find.text(goal))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isFalse,
        );
        semantics.dispose();
        if (capture != null) {
          await capture(tester, 'compact-agents-${brightness.name}-$scale');
        }
        await tester.ensureVisible(find.text('Read saved findings'));
        await tester.tap(find.text('Read saved findings'));
        await tester.pumpAndSettle();
        await tester.settleMarkdown();
        expect(
          find.text('Verified findings', findRichText: true),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('nested activity headers fit a phone at text scale $scale', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final fixture = ProfileActionsFixture();
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final controller = ProfileWorkspaceController(
        access: ConnectionAccess(
          connection: identityTestConnection(),
          dashboardOAuth: null,
        ),
        connectionIdentity: 'compact-details',
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: fixture.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final chat = await controller.createChat(canDispatch: () => true);
      final supervision = ProfileSupervisionSession(
        controller: controller,
        chat: chat,
      );
      addTearDown(supervision.dispose);
      emitChatEvent(controller, chat, 'subagent.start', {
        'subagent_id': 'one',
        'goal': 'Compare the available stays',
      });
      emitChatEvent(controller, chat, 'subagent.complete', {
        'subagent_id': 'two',
        'goal': 'Check privacy',
        'status': 'completed',
      });
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
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
                          content:
                              'Check the full list of available properties and compare privacy.',
                          status: GatewayTodoStatus.completed,
                        ),
                        GatewayTodo(
                          content: 'Review alternatives',
                          status: GatewayTodoStatus.pending,
                        ),
                      ],
                    ),
                    ProfileSubagentPanel(session: supervision),
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
          tester
              .getSize(find.byKey(const ValueKey(('activity-tab', 'tools'))))
              .height,
          lessThanOrEqualTo(32),
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
