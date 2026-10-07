import 'dart:convert';
import 'helpers/pump_markdown_widget.dart';
import 'package:wing/core/models/transcript_timeline.dart';
import 'package:wing/core/widgets/profile_tool_activity.dart';
import 'support/composer_fixture.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_actions_fixture.dart';

void main() {
  for (final category in ['tasks', 'agents']) {
    testWidgets('saved history restores the $category activity tab', (
      tester,
    ) async {
      final name = category == 'tasks' ? 'todo_list' : 'delegate_task';
      final arguments = category == 'tasks'
          ? <String, dynamic>{}
          : {
              'tasks': [
                {'goal': 'Inspect the saved delegation'},
              ],
            };
      final result = category == 'tasks'
          ? {
              'revision': 2,
              'todos': [
                {
                  'id': 'one',
                  'content': 'Inspect the saved task',
                  'status': 'completed',
                },
              ],
            }
          : {
              'results': [
                {
                  'task_index': 0,
                  'status': 'completed',
                  'summary': 'Inspection complete',
                  'duration_seconds': 42.5,
                  'model': 'test-model',
                  'api_calls': 3,
                },
              ],
              'total_duration_seconds': 43,
            };
      final rows = <Map<String, dynamic>>[
        {
          'id': 1,
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'call',
              'type': 'function',
              'function': {'name': name, 'arguments': jsonEncode(arguments)},
            },
          ],
        },
        {
          'id': 2,
          'role': 'tool',
          'tool_call_id': 'call',
          'content': jsonEncode(result),
        },
      ];
      final timeline = TranscriptTimeline.project(
        rows,
        presentationId: (row) => row['id']!,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ProfileToolActivitySection(section: timeline.sections.single),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      final tab = find.byKey(ValueKey(('activity-tab', category)));
      expect(tab, findsOneWidget);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(
        find.text(
          category == 'tasks'
              ? 'Inspect the saved task'
              : 'Inspect the saved delegation',
        ),
        findsOneWidget,
      );
      if (category == 'agents') {
        expect(find.text('43 s'), findsOneWidget);
        await tester.tap(find.text('Inspect the saved delegation'));
        await tester.pumpAndSettle();
        await tester.settleMarkdown();
        expect(
          find.text('Inspection complete', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('Steer'), findsNothing);
        expect(find.text('Interrupt'), findsNothing);
      }
    });
  }

  testWidgets('saved tool calls and current work share one Activity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final host = ProfileActionsFixture();
    final preferences = await SharedPreferences.getInstance();
    final appPreferences = AppPreferences(preferences);
    addTearDown(appPreferences.dispose);
    final controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'combined-activity',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final chat = await controller.createChat(canDispatch: () => true);
    chat.reading.installSavedHistory([
      ...chat.reading.messages,
      ...[
        {'id': 1, 'role': 'user', 'content': 'Continue searching'},
        for (var id = 2; id <= 68; id++)
          {
            'id': id,
            'role': 'tool',
            'tool_name': 'Search',
            'content': 'Result $id',
          },
      ],
    ]);
    emitChatEvent(controller, chat, 'tool.start', {
      'name': 'terminal',
      'tool_id': 'live',
    });
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Tool activity'), findsNothing);
    expect(find.text('68 tool calls'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsNWidgets(67));
    expect(find.text('Running command'), findsOneWidget);
    expect(find.text('Tools 68'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('profile-message-composer')),
      'Keep Activity open while typing',
    );
    await tester.pump();
    expect(find.text('Search'), findsNWidgets(67));
    expect(find.text('Running command'), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.text('Search').first),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search').first);
    await tester.pumpAndSettle();
    expect(find.text('Result 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
