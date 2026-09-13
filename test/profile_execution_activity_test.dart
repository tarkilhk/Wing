import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/models/gateway_todo.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/widgets/profile_execution_activity.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_workspace_controller_test.dart' show Host;

void main() {
  late Host host;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = Host();
    host.todoState = {
      'revision': 2,
      'todos': [
        {'id': 'one', 'content': 'Inspect contract', 'status': 'in_progress'},
      ],
    };
    controller = ProfileWorkspaceController(
      connectionIdentity: 'execution-test-host',
      connection: SavedConnection(
        id: 'host',
        label: 'Host',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
  });

  tearDown(() => controller.dispose());

  test('hydrates todos and rejects an older live revision', () {
    expect(chat.todoRevision, 2);
    expect(chat.todos.single.content, 'Inspect contract');
    expect(chat.todos.single.status, GatewayTodoStatus.inProgress);

    host.event('a', 'todo.updated', {
      'revision': 1,
      'todos': [
        {'id': 'old', 'content': 'Stale task', 'status': 'pending'},
      ],
    });
    expect(chat.todos.single.id, 'one');

    host.event('a', 'todo.updated', {
      'revision': 3,
      'todos': [
        {'id': 'one', 'content': 'Inspect contract', 'status': 'completed'},
        {'id': 'two', 'content': 'Render result', 'status': 'cancelled'},
      ],
    });
    expect(chat.todoRevision, 3);
    expect(chat.todos.map((todo) => todo.status), [
      GatewayTodoStatus.completed,
      GatewayTodoStatus.cancelled,
    ]);
  });

  test(
    'upserts live tool events and authoritative refresh removes completion',
    () async {
      host.event('a', 'tool.generating', {'name': 'search_files'});
      expect(chat.tool, 'search_files');
      expect(
        chat.toolActivities.single.phase,
        GatewayToolActivityPhase.generating,
      );

      host.event('a', 'tool.start', {
        'tool_id': 'tool-1',
        'name': 'search_files',
        'args': {'query': 'gateway'},
        'context': 'Workspace',
      });
      host.event('a', 'tool.progress', {
        'tool_id': 'tool-1',
        'name': 'search_files',
        'preview': 'Scanning',
      });
      expect(chat.toolActivities, hasLength(1));
      expect(chat.toolActivities.single.detail, 'Scanning');

      host.event('a', 'tool.complete', {
        'tool_id': 'tool-1',
        'name': 'search_files',
        'result': {'matches': 2},
        'duration_s': 1.5,
      });
      final completed = chat.toolActivities.single;
      expect(completed.phase, GatewayToolActivityPhase.completed);
      expect(completed.arguments, '{"query":"gateway"}');
      expect(completed.result, '{"matches":2}');
      expect(completed.statusLabel, 'Completed in 1.5 s');

      await controller.refreshHistory(chat);
      expect(chat.toolActivities, isEmpty);
    },
  );

  test(
    'reasoning appends, replaces, and stays with the runtime owner',
    () async {
      host.event('a', 'reasoning.delta', {'text': 'Check the '});
      host.event('a', 'reasoning.delta', {'text': 'contract.'});
      expect(chat.reasoning, 'Check the contract.');
      host.event('a', 'reasoning.available', {
        'text': 'Verified reasoning.',
        'verbose': true,
      });
      expect(chat.reasoning, 'Verified reasoning.');
      expect(chat.reasoningVerbose, isTrue);

      await controller.switchProfile('b');
      final other = await controller.createChat();
      host.event('a', 'reasoning.delta', {'text': ' Owner A'});
      expect(chat.reasoning, 'Verified reasoning. Owner A');
      expect(other.reasoning, isEmpty);
    },
  );

  testWidgets('renders expandable tool, todo, and reasoning details', (
    tester,
  ) async {
    final tool = GatewayToolActivity.fromGatewayEvent('tool.complete', {
      'tool_id': 'tool-1',
      'name': 'search_files',
      'args': {'query': 'gateway'},
      'result': {'matches': 2},
      'duration_s': 0.4,
    })!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ProfileLiveToolActivity(activities: [tool]),
              const ProfileTodoPanel(
                todos: [
                  GatewayTodo(
                    id: 'one',
                    content: 'Inspect contract',
                    status: GatewayTodoStatus.completed,
                  ),
                ],
              ),
              const ProfileReasoningDisclosure(text: 'Checked the contract.'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Completed in 400 ms'), findsNothing);
    await tester.tap(find.text('Current tools'));
    await tester.pumpAndSettle();
    expect(find.text('Completed in 400 ms'), findsOneWidget);
    await tester.tap(find.text('Search files'));
    await tester.pumpAndSettle();
    expect(find.text('{"query":"gateway"}'), findsOneWidget);
    expect(find.text('{"matches":2}'), findsOneWidget);
    expect(find.text('Inspect contract'), findsNothing);
    await tester.tap(find.text('Tasks 1/1'));
    await tester.pumpAndSettle();
    expect(find.text('Inspect contract'), findsOneWidget);
    expect(find.text('Checked the contract.'), findsNothing);
    await tester.tap(find.text('Thought'));
    await tester.pumpAndSettle();
    expect(find.text('Checked the contract.'), findsOneWidget);
  });

  testWidgets(
    'running tool activity stays collapsed through draft rebuilds until tapped',
    (tester) async {
      final tool = GatewayToolActivity.fromGatewayEvent('tool.start', {
        'tool_id': 'tool-running',
        'name': 'search_files',
        'args': {'query': 'gateway'},
      })!;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Column(
                children: [
                  TextField(
                    key: const ValueKey('draft'),
                    onChanged: (_) => setState(() {}),
                  ),
                  ProfileLiveToolActivity(activities: [tool]),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Search files'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('draft')), 'typing');
      await tester.pump();
      expect(find.text('Search files'), findsNothing);

      await tester.tap(find.text('Current tools'));
      await tester.pumpAndSettle();
      expect(find.text('Search files'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('draft')),
        'typing more',
      );
      await tester.pump();
      expect(find.text('Search files'), findsOneWidget);
    },
  );

  test('reads verified historical reasoning fields', () {
    expect(
      profileMessageReasoning({
        'reasoning_content': 'Stored reasoning',
        'content': 'Answer',
      }),
      'Stored reasoning',
    );
    expect(
      profileMessageReasoning({
        'reasoning_details': {'hidden': true},
      }),
      '',
    );
  });
}
