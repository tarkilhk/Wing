import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/profile_saved_agents.dart';

import 'helpers/pump_markdown_widget.dart';
import 'package:wing/core/models/gateway_todo.dart';
import 'package:wing/core/models/transcript_message.dart';
import 'package:wing/core/presentation/saved_activity.dart';

TranscriptToolResult call(String name, Object output, {Object? args}) =>
    TranscriptToolResult.fromRow({
      'role': 'tool',
      'tool_name': name,
      'content': jsonEncode(output),
      'args': ?args,
    });

void main() {
  test(
    'latest full task snapshot preserves order/status and empty clears it',
    () {
      final older = call('todo_list', {
        'revision': 1,
        'todos': [
          {'id': 'old', 'content': 'Superseded', 'status': 'pending'},
        ],
      });
      final newer = call('todo_list', {
        'revision': 2,
        'todos': [
          {'id': 'parent', 'content': 'Parent', 'status': 'in_progress'},
          {
            'id': 'child',
            'content': 'Child',
            'status': 'cancelled',
            'parent': 'parent',
          },
        ],
      });
      final saved = SavedActivity([older, newer]);
      expect(saved.todos.map((t) => t.content), ['Parent', 'Child']);
      expect(saved.todos.last.status, GatewayTodoStatus.cancelled);
      expect(saved.todos.last.parent, 'parent');
      expect(
        SavedActivity([
          older,
          call('todo_list', {'revision': 2, 'todos': []}),
        ]).todos,
        isEmpty,
      );
    },
  );

  test('delegation goals use the exact task index, never result order', () {
    final saved = SavedActivity([
      call(
        'delegate_task',
        {
          'results': [
            {
              'task_index': 1,
              'status': 'failed',
              'error': 'Unavailable',
              'duration_seconds': 2.5,
            },
            {'task_index': 0, 'status': 'completed', 'summary': 'Done'},
            {'task_index': 3, 'status': 'timeout', 'duration_seconds': -1},
          ],
        },
        args: {
          'tasks': [
            {'goal': 'First'},
            {'goal': 'Second'},
          ],
        },
      ),
    ]);
    expect(saved.agents.map((a) => a.goal), [
      'Second',
      'First',
      'Delegated task',
    ]);
    expect(saved.agents.first.notice, 'Failed');
    expect(saved.agents.first.durationSeconds, 2.5);
    expect(saved.agents[1].notice, isNull);
    expect(saved.agents.last.durationSeconds, isNull);
  });

  test(
    'saved background dispatch describes a past dispatch, never live work',
    () {
      final saved = SavedActivity([
        call('delegate_task', {
          'status': 'dispatched',
          'mode': 'background',
          'goals': ['Background', 'Inline'],
          'inline_results': [
            {'task_index': 1, 'status': 'completed', 'duration_seconds': 9},
          ],
        }),
      ]);
      expect(saved.agents.map((a) => a.goal), ['Background', 'Inline']);
      expect(saved.agents.first.notice, 'Dispatched in background');
      expect(saved.agents.first.durationSeconds, isNull);
      expect(saved.agents.last.durationSeconds, 9);
    },
  );

  test(
    'child termination and schema observations stay independently qualified',
    () {
      final saved = SavedActivity([
        call(
          'delegate_task',
          {
            'results': [
              {
                'task_index': 0,
                'status': 'completed',
                'summary': 'Partial research',
                'exit_reason': 'max_iterations',
                'truncated': true,
                'schema_valid': false,
                'schema_note': 'A required field is missing',
                'schema_errors': ['Missing findings'],
              },
              {
                'task_index': 1,
                'status': 'completed',
                'summary_truncated': true,
              },
              {'task_index': 2, 'status': 'completed'},
            ],
          },
          args: {
            'tasks': [
              {'goal': 'First'},
              {'goal': 'Second'},
              {'goal': 'Third'},
            ],
          },
        ),
      ]);
      final limited = saved.agents.first;
      expect(limited.statusLabel, 'Completed');
      expect(limited.failed, isFalse);
      expect(limited.warning, isTrue);
      expect(limited.qualifications, [
        'Stopped at the iteration limit',
        'Output does not meet the requested schema',
      ]);
      expect(limited.schemaNote, 'A required field is missing');
      expect(limited.schemaErrors, ['Missing findings']);
      expect(() => limited.schemaErrors.add('Changed'), throwsUnsupportedError);
      expect(saved.agents[1].qualifications, [
        'Summary shortened by the server',
      ]);
      expect(saved.agents.last.schemaValid, isNull);
      expect(saved.agents.last.truncated, isNull);
      expect(saved.agents.last.warning, isFalse);
      expect(saved.agents.last.qualifications, isEmpty);
    },
  );

  test(
    'saved unknown status stays neutral and unavailable task is not authored',
    () {
      final result = SavedActivity([
        call(
          'delegate_task',
          {
            'results': [
              {'task_index': 3, 'status': 'pending_review'},
            ],
          },
          args: {'goal': 'Unadvertised flat input'},
        ),
      ]).agents.single;
      expect(result.goal, 'Delegated task');
      expect(result.goalSupplied, isFalse);
      expect(result.statusLabel, 'pending review');
      expect(result.terminal, isFalse);
      expect(result.warning, isFalse);
      expect(result.failed, isFalse);
    },
  );

  test('raw child receipt retains exact delivered call bytes', () {
    const raw = '{ "results": [{ "task_index": 0, "status": "completed" }] }';
    final result = SavedActivity([
      TranscriptToolResult.fromRow({
        'role': 'tool',
        'tool_name': 'delegate_task',
        'content': raw,
      }),
    ]).agents.single;
    expect(result.rawDetails, raw);
  });

  testWidgets(
    'empty completed and dispatch receipts retain task and actual state',
    (tester) async {
      final agents = SavedActivity([
        call(
          'delegate_task',
          {
            'results': [
              {'task_index': 0, 'status': 'completed'},
            ],
          },
          args: {
            'tasks': [
              {'goal': 'Inspect the report'},
            ],
          },
        ),
        call('delegate_task', {
          'status': 'dispatched',
          'goals': ['Continue in background'],
        }),
      ]).agents;
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.light),
          home: Scaffold(
            body: ListView(children: [ProfileSavedAgents(agents: agents)]),
          ),
        ),
      );
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Dispatched in background'), findsOneWidget);
      await tester.tap(find.text('Inspect the report'));
      await tester.pumpAndSettle();
      expect(find.text('Task'), findsOneWidget);
      expect(find.text('No result supplied'), findsOneWidget);
      expect(find.byTooltip('Copy Task'), findsOneWidget);
      expect(find.byTooltip('Copy Output'), findsNothing);
      await tester.tap(find.text('Continue in background'));
      await tester.pumpAndSettle();
      expect(find.text('Task'), findsNWidgets(2));
      expect(find.text('No result supplied'), findsOneWidget);
      expect(find.byTooltip('Steer'), findsNothing);
      expect(find.byTooltip('Interrupt'), findsNothing);
    },
  );

  testWidgets(
    'failure explanation appears once and unavailable task has no copy',
    (tester) async {
      final agents = SavedActivity([
        call('delegate_task', {
          'results': [
            {
              'task_index': 0,
              'status': 'failed',
              'summary': 'Provider rejected the request',
              'error': 'Provider rejected the request',
            },
          ],
        }),
      ]).agents;
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: Scaffold(
            body: ListView(children: [ProfileSavedAgents(agents: agents)]),
          ),
        ),
      );
      await tester.tap(find.text('Delegated task'));
      await tester.pumpAndSettle();
      expect(find.text('Provider rejected the request'), findsOneWidget);
      expect(find.text('Failed'), findsNWidgets(2));
      expect(find.text('Output'), findsNothing);
      expect(find.byTooltip('Copy Task'), findsNothing);
      expect(find.byTooltip('Copy Error'), findsNothing);
      expect(find.byTooltip('Copy Raw details'), findsNothing);
    },
  );

  testWidgets('qualified output copy retains exact received summary', (
    tester,
  ) async {
    const summary = '  Useful **partial** report.\n';
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final agents = SavedActivity([
      call(
        'delegate_task',
        {
          'results': [
            {
              'task_index': 0,
              'status': 'completed',
              'summary': summary,
              'exit_reason': 'max_iterations',
              'truncated': true,
              'schema_valid': false,
              'schema_note': 'The requested structure is missing',
              'schema_errors': ['Missing evidence field'],
            },
          ],
        },
        args: {
          'tasks': [
            {'goal': 'Collect evidence'},
          ],
        },
      ),
    ]).agents;
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.light),
        home: Scaffold(
          body: ListView(children: [ProfileSavedAgents(agents: agents)]),
        ),
      ),
    );
    await tester.tap(find.text('Collect evidence'));
    await tester.pumpAndSettle();
    await tester.settleMarkdown();
    expect(find.text('Stopped at the iteration limit'), findsOneWidget);
    expect(
      find.text('Output does not meet the requested schema'),
      findsOneWidget,
    );
    expect(find.text('Missing evidence field'), findsOneWidget);
    expect(find.text('Failed'), findsNothing);
    await tester.ensureVisible(find.byTooltip('Copy Output'));
    await tester.tap(find.byTooltip('Copy Output'));
    await tester.pump();
    expect(copied, summary);
    expect(find.byTooltip('Copy Schema finding'), findsNothing);
    expect(find.byTooltip('Copy Output qualification'), findsNothing);
  });

  test(
    'ordinary results and malformed payloads create no activity categories',
    () {
      final saved = SavedActivity([
        call('web_extract', {
          'results': [
            {'task_index': 0, 'status': 'completed'},
          ],
        }),
        call('search_files', {
          'todos': ['mention'],
        }),
        call('delegate_task', {
          'results': [
            {'task_index': '0', 'status': 'completed'},
          ],
        }),
        TranscriptToolResult.fromRow({'content': 'not JSON'}),
      ]);
      expect(saved.agents, isEmpty);
      expect(saved.todos, isEmpty);
    },
  );
}
