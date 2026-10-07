import 'package:wing/core/models/transcript_timeline.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/gateway_activity.dart';
import 'package:wing/core/models/gateway_todo.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/profile_execution_activity.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_workspace_controller_test.dart' show Host;

void main() {
  late Host host;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;
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
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      connectionIdentity: 'execution-test-host',
      access: ConnectionAccess(
        connection: SavedConnection(
          id: 'host',
          label: 'Host',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        dashboardOAuth: null,
      ),
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat(canDispatch: () => true);
  });

  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });

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
    expect(chat.todos.single.content, 'Inspect contract');
    expect(chat.todos.single.status, GatewayTodoStatus.inProgress);

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
      expect(chat.runtime.tool, 'search_files');
      expect(chat.runtime.toolActivities, isEmpty);

      host.event('a', 'tool.start', {
        'tool_id': 'tool-1',
        'name': 'search_files',
        'args': {'query': 'gateway'},
        'context': 'Workspace',
      });
      expect(chat.runtime.toolActivities, hasLength(1));
      expect(chat.runtime.toolActivities.single.detail, 'Workspace');

      host.event('a', 'tool.complete', {
        'tool_id': 'tool-1',
        'name': 'search_files',
        'result': {'matches': 2},
        'duration_s': 1.5,
      });
      final completed = chat.runtime.toolActivities.single;
      expect(completed.phase, GatewayToolActivityPhase.completed);
      expect(completed.arguments, '{"query":"gateway"}');
      expect(completed.result, '{"matches":2}');
      expect(completed.statusLabel, 'Completed in 1.5 s');

      host.historyMessages = [
        {
          'id': 21,
          'role': 'tool',
          'tool_call_id': 'tool-1',
          'content': '{"matches":2}',
        },
        {
          'id': 22,
          'role': 'tool',
          'tool_call_id': 'unrelated',
          'content': 'other',
        },
      ];
      await controller.refreshHistory(chat);
      expect(chat.runtime.toolActivities, isEmpty);
      final saved = TranscriptTimeline.project(
        chat.reading.messages,
        presentationId: chat.reading.messagePresentationId,
      );
      expect(saved.entries.first.tool!.durationSeconds, 1.5);
      expect(saved.entries.first.tool!.arguments, '{"query":"gateway"}');
      expect(saved.entries.last.tool!.durationSeconds, isNull);
    },
  );

  test(
    'reasoning appends, replaces, and stays with the runtime owner',
    () async {
      host.event('a', 'reasoning.delta', {'text': 'Check the '});
      host.event('a', 'reasoning.delta', {'text': 'contract.'});
      expect(chat.runtime.reasoning, 'Check the contract.');
      host.event('a', 'reasoning.available', {
        'text': 'Verified reasoning.',
        'verbose': true,
      });
      expect(chat.runtime.reasoning, 'Verified reasoning.');

      await controller.switchProfile('b');
      final other = await controller.createChat(canDispatch: () => true);
      host.event('a', 'reasoning.delta', {'text': ' Owner A'});
      expect(chat.runtime.reasoning, 'Verified reasoning. Owner A');
      expect(other.runtime.reasoning, isEmpty);
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('task states remain readable in ${brightness.name} at $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: ProfileTodoPanel(
                  embedded: true,
                  todos: [
                    GatewayTodo(
                      content: 'Inspect the rental conditions',
                      status: GatewayTodoStatus.completed,
                    ),
                    GatewayTodo(
                      content: 'Check the permitted travel area',
                      status: GatewayTodoStatus.inProgress,
                      parent: 'inspect',
                    ),
                    GatewayTodo(
                      content:
                          'Compare the available pickup locations and opening hours',
                      status: GatewayTodoStatus.pending,
                    ),
                    GatewayTodo(
                      content: 'Check an alternative supplier',
                      status: GatewayTodoStatus.cancelled,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            '1 of 4 completed · 1 in progress · 1 pending · 1 cancelled',
          ),
          findsOneWidget,
        );
        expect(find.text('Subtask · In progress'), findsOneWidget);
        expect(find.text('Pending'), findsOneWidget);
        expect(find.text('Cancelled'), findsOneWidget);
        expect(find.byType(Checkbox), findsNothing);
        expect(find.byType(SelectableText), findsNWidgets(4));
        final texts = tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((w) => w.data)
            .toList();
        expect(texts.first, 'Inspect the rental conditions');
        expect(texts.last, 'Check an alternative supplier');
        expect(tester.takeException(), isNull);
      });
    }
  }

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

    expect(find.text('400 ms'), findsOneWidget);
    await tester.tap(find.text('Searched files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Raw details'));
    await tester.pumpAndSettle();
    expect(find.text('{"query":"gateway"}'), findsOneWidget);
    expect(find.text('{"matches":2}'), findsOneWidget);
    await tester.tap(find.text('Raw details'));
    await tester.pumpAndSettle();
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

      expect(find.text('Searching files'), findsOneWidget);
      expect(find.text('Raw details'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('draft')), 'typing');
      await tester.pump();
      expect(find.text('Searching files'), findsOneWidget);
      expect(find.text('Raw details'), findsNothing);

      await tester.tap(find.text('Searching files'));
      await tester.pumpAndSettle();
      expect(find.text('Raw details'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('draft')),
        'typing more',
      );
      await tester.pump();
      expect(find.text('Raw details'), findsOneWidget);
    },
  );

  test('reads verified historical reasoning fields', () {
    expect(
      TranscriptTimeline.project([
        {'reasoning_content': 'Stored reasoning', 'content': 'Answer'},
      ], presentationId: (_) => Object()).entries.single.reasoning,
      'Stored reasoning',
    );
    expect(
      TranscriptTimeline.project([
        {
          'reasoning_details': {'hidden': true},
        },
      ], presentationId: (_) => Object()).entries.single.reasoning,
      '',
    );
  });
}
