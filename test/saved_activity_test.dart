import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
    expect(saved.agents.first.notice, 'Unavailable');
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
