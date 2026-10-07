import 'dart:async';

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
import 'package:wing/core/services/transcript_reading.dart';
import 'package:wing/core/services/workspace_snapshot_store.dart';
import 'package:wing/core/models/transcript_reading.dart';
import 'package:wing/core/services/profile_gateway.dart';
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

  test(
    'history recovers durations for tool completions missed while away',
    () async {
      host.historyMessages = [
        {
          'id': 21,
          'role': 'tool',
          'tool_call_id': 'missed',
          'tool_name': 'read_file',
          'content': 'Booking confirmed',
        },
      ];
      host.notificationReplay = {
        'events': [
          {
            'type': 'tool.complete',
            'session_id': chat.runtime.runtimeId,
            'seq': 7,
            'payload': {
              'tool_id': 'missed',
              'name': 'read_file',
              'args': {'path': 'trip/bookings.json'},
              'result': 'Booking confirmed',
              'duration_s': 0.195,
            },
          },
        ],
        'latest_seq': 7,
        'count': 1,
        'truncated': false,
        'epoch': 'server-process',
        'open_requests': [],
      };
      await controller.refreshHistory(chat);
      final timeline = TranscriptTimeline.project(
        chat.reading.messages,
        presentationId: chat.reading.messagePresentationId,
      );
      expect(timeline.entries.single.tool!.durationSeconds, 0.195);
      expect(
        timeline.entries.single.tool!.arguments,
        contains('trip/bookings.json'),
      );
      expect(chat.runtime.toolActivities, isEmpty);
      expect(
        chat.reading.captureSnapshot().messages.single['duration_s'],
        0.195,
      );
    },
  );

  test(
    'partial replay enriches only matching completed calls without reviving work',
    () async {
      const ids = ['measured', 'missing', 'zero', 'wrong-runtime', 'running'];
      host.historyMessages = [
        for (final (index, id) in ids.indexed)
          {
            'id': 21 + index,
            'role': 'tool',
            'tool_call_id': id,
            'tool_name': 'read_file',
            'content': 'File contents',
          },
      ];
      Map<String, dynamic> event(
        String id,
        Object? seconds, {
        String type = 'tool.complete',
        String? runtime,
      }) => {
        'type': type,
        'session_id': runtime ?? chat.runtime.runtimeId,
        'payload': {'tool_id': id, 'name': 'read_file', 'duration_s': seconds},
      };
      host.notificationReplay = {
        'events': [
          event('measured', 0.1),
          event('measured', 0.195),
          event('missing', -1),
          event('missing', '0.2'),
          event('zero', 0),
          event('wrong-runtime', 99, runtime: 'b-runtime'),
          event('running', 99, type: 'tool.start'),
          event('not-in-history', 99),
          {
            'type': 'turn.end',
            'session_id': chat.runtime.runtimeId,
            'payload': {},
          },
        ],
        'truncated': true,
      };
      final execution = chat.runtime.execution;
      await controller.refreshHistory(chat);
      expect(chat.reading.messages, hasLength(5));
      expect(chat.reading.messages.map((row) => row['duration_s']).toList(), [
        0.195,
        null,
        0,
        null,
        null,
      ]);
      expect(chat.runtime.toolActivities, isEmpty);
      expect(chat.runtime.execution, execution);
      expect(
        host.calls.lastWhere((call) => call.$2 == 'session.events.since').$3,
        {'session_id': chat.runtime.runtimeId, 'last_seen': 0, 'profile': 'a'},
      );
    },
  );

  test(
    'bounded recovery retains newest durations in a full replay ring',
    () async {
      host.historyMessages = [
        for (final id in [0, 511])
          {
            'id': id + 1,
            'role': 'tool',
            'tool_call_id': 'call-$id',
            'content': 'File contents',
          },
      ];
      host.notificationReplay = {
        'events': [
          for (var id = 0; id < 512; id++)
            {
              'type': 'tool.complete',
              'session_id': chat.runtime.runtimeId,
              'payload': {
                'tool_id': 'call-$id',
                'name': 'read_file',
                'duration_s': id / 1000,
              },
            },
        ],
      };
      await controller.refreshHistory(chat);
      expect(chat.reading.messages.first['duration_s'], isNull);
      expect(chat.reading.messages.last['duration_s'], .511);
    },
  );

  test('failed timing recovery keeps saved history readable', () async {
    host.historyMessages = [
      {
        'id': 21,
        'role': 'tool',
        'tool_call_id': 'missing',
        'content': 'File contents',
      },
    ];
    final base = host.gateway(chat.key.workspace);
    final reading = TranscriptReading(
      gateway: ProfileGateway(
        scope: chat.key.workspace,
        discover: base.discover,
        get: base.read,
        rpc: (method, params) async {
          if (method == 'session.events.since') {
            throw StateError('Connection lost');
          }
          return base.call(method, params);
        },
      ),
    );
    addTearDown(reading.dispose);
    expect(
      await reading.refresh(
        sessionId: chat.key.sessionId,
        runtimeId: chat.runtime.runtimeId,
        canPublish: () => true,
        onChanged: () {},
      ),
      isTrue,
    );
    expect(reading.messages.single['content'], 'File contents');
    expect(reading.messages.single['duration_s'], isNull);
    expect(reading.historyError, isNull);
  });

  test(
    'late timing recovery cannot overwrite live completion or a retired read',
    () async {
      for (final retired in [false, true]) {
        host.historyMessages = [
          {
            'id': 21,
            'role': 'tool',
            'tool_call_id': 'measured',
            'content': 'File contents',
          },
        ];
        final held = Completer<Map<String, dynamic>>();
        final started = Completer<void>();
        final base = host.gateway(chat.key.workspace);
        final reading = TranscriptReading(
          gateway: ProfileGateway(
            scope: chat.key.workspace,
            discover: base.discover,
            get: base.read,
            rpc: (method, params) async {
              if (method == 'session.events.since') {
                started.complete();
                return held.future;
              }
              return base.call(method, params);
            },
          ),
        );
        addTearDown(reading.dispose);
        var current = true;
        final refresh = reading.refresh(
          sessionId: chat.key.sessionId,
          runtimeId: chat.runtime.runtimeId,
          canPublish: () => current,
          onChanged: () {},
        );
        await started.future;
        reading.observeTool(
          GatewayToolActivity.fromGatewayEvent('tool.complete', {
            'tool_id': 'measured',
            'name': 'read_file',
            'duration_s': .42,
          })!,
        );
        if (retired) current = false;
        held.complete({
          'events': [
            {
              'type': 'tool.complete',
              'session_id': chat.runtime.runtimeId,
              'payload': {
                'tool_id': 'measured',
                'name': 'read_file',
                'duration_s': .195,
              },
            },
          ],
        });
        expect(await refresh, !retired);
        if (retired) {
          expect(reading.messages, isEmpty);
        } else {
          expect(reading.messages.single['duration_s'], .42);
        }
      }
    },
  );

  test(
    'received durations survive cached reading and authoritative refresh',
    () async {
      host.event('a', 'tool.complete', {
        'tool_id': 'measured',
        'name': 'browser_exec',
        'args': {'code': 'open("https://example.org/rentals")'},
        'result': {'stdout': 'Rental terms'},
        'duration_s': 1.25,
      });
      host.historyMessages = [
        {
          'id': 21,
          'role': 'tool',
          'tool_call_id': 'measured',
          'content': 'Rental terms',
        },
        {
          'id': 22,
          'role': 'tool',
          'tool_call_id': 'unmeasured',
          'content': 'Other terms',
        },
      ];
      await controller.refreshHistory(chat);
      expect(chat.reading.messages.first['duration_s'], 1.25);
      final store = WorkspaceSnapshotStore(
        await SharedPreferences.getInstance(),
        'tool-timing',
      );
      await store.write({
        'profiles': [
          {
            'chats': [
              {'messages': chat.reading.captureSnapshot().messages},
            ],
          },
        ],
      });
      final rows = (store.read()['profiles'][0]['chats'][0]['messages'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final restored = TranscriptReading(
        gateway: host.gateway(chat.key.workspace),
      );
      addTearDown(restored.dispose);
      restored.installSnapshot(
        TranscriptReadingSnapshot(messages: rows, historySessionId: 'same'),
      );
      expect(restored.messages.first['duration_s'], 1.25);
      expect(restored.messages.first['args'], contains('example.org/rentals'));
      restored.installSavedPage(
        ProfileHistoryPage(
          'same',
          host.historyMessages!,
          0,
          500,
          isComplete: true,
        ),
      );
      final timeline = TranscriptTimeline.project(
        restored.messages,
        presentationId: restored.messagePresentationId,
      );
      expect(timeline.entries.first.tool!.durationSeconds, 1.25);
      expect(timeline.entries.first.tool!.callId, 'measured');
      expect(timeline.entries.last.tool!.durationSeconds, isNull);
      restored.installSavedPage(
        ProfileHistoryPage(
          'same',
          [
            // Same call text/ID with a different durable row is not the same result.
            {
              'id': 31,
              'role': 'tool',
              'tool_call_id': 'measured',
              'content': 'Rental terms',
            },
            {
              'id': 21,
              'role': 'tool',
              'tool_call_id': 'other-call',
              'content': 'Rental terms',
            },
          ],
          0,
          500,
          isComplete: true,
        ),
      );
      expect(
        restored.messages.every((row) => row['duration_s'] == null),
        isTrue,
      );
      restored.installSavedPage(
        ProfileHistoryPage(
          'same',
          [
            {
              'id': 21,
              'role': 'tool',
              'tool_call_id': 'measured',
              'content': 'Rental terms',
            },
          ],
          0,
          500,
          isComplete: true,
        ),
      );
      restored.observeTool(
        GatewayToolActivity.fromGatewayEvent('tool.complete', {
          'tool_id': 'measured',
          'name': 'browser_exec',
          'duration_s': 0,
          'result': 'Rental terms',
        })!,
      );
      expect(
        restored.messages.singleWhere((row) => row['id'] == 21)['duration_s'],
        0,
      );
      restored.installSavedPage(
        ProfileHistoryPage(
          'same',
          host.historyMessages!,
          0,
          500,
          isComplete: true,
        ),
      );
      expect(
        restored.messages.singleWhere((row) => row['id'] == 21)['duration_s'],
        0,
      );
    },
  );

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
