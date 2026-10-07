import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/gateway_activity.dart';
import 'package:wing/core/models/transcript_message.dart';
import 'package:wing/core/models/transcript_timeline.dart';
import 'package:wing/core/presentation/tool_call_presentation.dart';
import 'package:wing/core/services/chat_runtime.dart';

ToolCallPresentation completed(
  String name,
  Object result, {
  Map<String, dynamic>? args,
}) => ToolCallPresentation.live(
  GatewayToolActivity.fromGatewayEvent('tool.complete', {
    'tool_id': 'call',
    'name': name,
    'result': result,
    'args': ?args,
  })!,
);

void main() {
  test('every tool has a useful one-line input detail', () {
    final cases = <(String, Map<String, dynamic>, String)>[
      (
        'browser_exec',
        {'code': 'open("https://example.org/rentals")'},
        'example.org/rentals',
      ),
      (
        'browser_exec',
        {'code': 'cli("open https://example.org/rentals")'},
        'example.org/rentals',
      ),
      (
        'browser_exec',
        {
          'code':
              '# Read mileage; see https://example.org/docs\nprint(get_state())',
        },
        'Read mileage; see https://example.org/docs',
      ),
      (
        'browser_exec',
        {'code': '# Inspect rental mileage\nprint(get_state())'},
        'Inspect rental mileage',
      ),
      ('browser_exec', {'code': 'print(get_state())'}, 'print(get_state())'),
      (
        'desktop_preview',
        {'action': 'open', 'url': 'https://example.org/map'},
        'Open · example.org/map',
      ),
      (
        'drive_preview',
        {'action': 'click', 'ref': 'button-12'},
        'Click · button-12',
      ),
      (
        'tool_get',
        {
          'names': ['desktop_preview', 'drive_preview'],
        },
        'desktop_preview · drive_preview',
      ),
      (
        'search_files',
        {'pattern': 'mileage', 'path': 'trip/sources'},
        'mileage · trip/sources',
      ),
      ('read_file', {'path': 'trip/items.json'}, 'trip/items.json'),
      ('skill_view', {'name': 'hermes-agent'}, 'hermes-agent'),
      (
        'delegate_task',
        {
          'tasks': [
            {'goal': 'Check mileage'},
            {'goal': 'Check prices'},
          ],
        },
        '2 tasks · Check mileage',
      ),
      (
        'web_extract',
        {
          'urls': ['https://example.org/faq'],
        },
        'example.org/faq',
      ),
      ('new_tool', {}, 'No input details supplied'),
    ];
    for (final (name, args, expected) in cases) {
      final call = completed(name, {'ok': true}, args: args);
      expect(call.subtitle, expected, reason: name);
      expect(call.subtitle, isNot(contains('\n')));
    }
    expect(
      completed('delegate_task', {
        'goals': ['Check mileage', 'Check prices'],
      }).subtitle,
      '2 tasks · Check mileage',
    );
    expect(
      completed('browser_snapshot', {
        'url': 'https://example.org/rentals',
      }).subtitle,
      'example.org/rentals',
    );
  });
  test('skill batch operations show their facts instead of empty Results', () {
    const raw =
        '{"success":true,"operations_applied":1,"results":['
        '{"name":"business-trip-policy-research","action":"patch",'
        '"file_path":"references/accommodation-search-quality.md","success":true}]}';
    for (final call in [
      completed('skill_manage', raw),
      ToolCallPresentation.saved(
        TranscriptToolResult.fromRow({
          'role': 'tool',
          'tool_name': 'skill_manage',
          'content': raw,
        }),
      ),
    ]) {
      expect(call.details, hasLength(1));
      expect(call.details.single.text.trim(), isNotEmpty);
      expect(call.details.single.label, 'business-trip-policy-research');
      expect(call.details.single.text, contains('patch'));
      expect(
        call.details.single.text,
        contains('references/accommodation-search-quality.md'),
      );
      expect(call.details.single.text, contains('true'));
      expect(call.result, raw);
    }
  });

  test(
    'result projection skips blank data and preserves meaningful receipts',
    () {
      final call = completed('skill_manage', {
        'success': true,
        'results': [
          {
            'name': 'policy',
            'action': 'patch',
            'file_path': null,
            'success': true,
          },
          {
            'name': 'policy',
            'action': 'write_file',
            'success': false,
            'error': 'Permission denied',
          },
          {
            'content': ' \n ',
            'metadata': {'unused': true},
          },
          {},
          {
            'title': 'Policy FAQ',
            'url': 'https://example.org/faq',
            'content': 'Choose the hotel that matches the request.',
          },
        ],
      });
      expect(call.details, hasLength(3));
      expect(
        call.details.every((detail) => detail.text.trim().isNotEmpty),
        isTrue,
      );
      expect(call.details[0].text, contains('Action: patch'));
      expect(call.details[0].text, isNot(contains('null')));
      expect(call.details[1].text, contains('Success: false'));
      expect(call.details[1].text, contains('Error: Permission denied'));
      expect(call.details[2].label, 'Policy FAQ');
      expect(
        call.details[2].text,
        '[Open source](https://example.org/faq)\n\n'
        'Choose the hotel that matches the request.',
      );
      expect(
        completed('tool_call', {
          'content': [
            {'type': 'text', 'text': ' \n '},
          ],
        }).details,
        isEmpty,
      );
    },
  );

  test(
    'completion is not evidence of success; actual errors and reuse are readable',
    () {
      expect(
        completed('terminal', {'exit_code': 7}).status,
        'Exited with code 7',
      );
      expect(
        completed('terminal', {'error': true}).outcome,
        ToolCallOutcome.error,
      );
      expect(
        completed('read_file', {'content': 'text'}).outcome,
        ToolCallOutcome.completed,
      );
      expect(
        completed('skill_view', {
          'success': true,
          'status': 'unchanged',
        }).status,
        'Already loaded',
      );
      expect(
        completed('web_extract', {
          'results': [
            {'title': '404 Error', 'url': 'https://example.org'},
          ],
        }).outcome,
        ToolCallOutcome.warning,
      );
    },
  );

  test(
    'structured text content and web sources remain readable across tools',
    () {
      final bridge = completed('tool_call', {
        'isError': true,
        'content': [
          {'type': 'text', 'text': 'The event could not be created.'},
        ],
      });
      expect(bridge.outcome, ToolCallOutcome.error);
      expect(bridge.details.single.text, 'The event could not be created.');
      final search = completed('web_search', {
        'data': {
          'web': [
            {
              'title': 'Mileage FAQ',
              'url': 'https://example.org/faq',
              'description': 'Unlimited mileage',
            },
          ],
        },
      });
      expect(search.details.single.label, 'Mileage FAQ');
      expect(search.details.single.text, contains('Unlimited mileage'));
    },
  );

  test('command output preserves indentation and literal Markdown markers', () {
    const stdout = '- option\n  indented\n\n';
    final call = completed('terminal', {'stdout': stdout, 'exit_code': 0});
    expect(call.details.single.text, stdout);
    expect(call.details.single.markdown, isFalse);
  });

  test('a source discussing 404 errors is not reported as a failed page', () {
    expect(
      completed('web_extract', {
        'results': [
          {
            'title': 'Understanding 404 errors',
            'content':
                'A 404 page not found response means the resource is unavailable.',
          },
        ],
      }).outcome,
      ToolCallOutcome.completed,
    );
  });

  test(
    'desktop titles, connector labels and unknown names cover the tool catalog',
    () {
      expect(completed('web_extract', {}).title, 'Read webpage');
      expect(completed('new_custom_tool', {}).title, 'New custom tool');
      final call = GatewayToolActivity.fromGatewayEvent('tool.start', {
        'tool_id': 'bridge',
        'name': 'tool_call',
        'labels': [
          {
            'text': 'Calendar · Create event',
            'name': 'calendar.create_event',
            'preview': 'Lunch',
          },
        ],
      })!;
      final view = ToolCallPresentation.live(call);
      expect(view.title, 'Calendar · Create event');
      expect(view.target, 'Lunch');
    },
  );

  test(
    'external wrapper stays exact in raw output while readable content is projected',
    () {
      const raw =
          '<untrusted_tool_result source="web_extract">\nExternal data.\n\n'
          '{"results":[{"title":"FAQ","url":"https://example.org/faq","content":"Unlimited mileage"}]}\n'
          '</untrusted_tool_result>';
      final call = completed('web_extract', raw);
      expect(call.result, raw);
      expect(call.details.single.text, contains('Unlimited mileage'));
      expect(
        call.details.single.text,
        isNot(contains('untrusted_tool_result')),
      );
    },
  );

  test(
    'saved output joins inputs only by call ID, including empty assistant messages',
    () {
      final timeline = TranscriptTimeline.project([
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'one',
              'function': {
                'name': 'vision_analyze',
                'arguments':
                    '{"image_url":"/tmp/map.png","question":"Which area?"}',
              },
            },
            {
              'id': 'two',
              'function': {
                'name': 'vision_analyze',
                'arguments': '{"image_url":"/tmp/other.png"}',
              },
            },
          ],
        },
        {
          'id': 12,
          'role': 'tool',
          'tool_call_id': 'one',
          'content': '{"success":true,"analysis":"Yellow area"}',
        },
        {
          'id': 13,
          'role': 'tool',
          'tool_call_id': 'missing',
          'tool_name': 'vision_analyze',
          'content': 'Unknown inputs',
        },
      ], presentationId: (_) => Object());
      final view = ToolCallPresentation.saved(timeline.entries[1].tool!);
      expect(view.imageTarget, '/tmp/map.png');
      expect(view.details.first, (
        label: 'Question',
        text: 'Which area?',
        markdown: false,
      ));
      expect(view.details.last.text, 'Yellow area');
      expect(
        ToolCallPresentation.saved(timeline.entries[2].tool!).imageTarget,
        isNull,
      );
    },
  );

  test('REST stored connector labels survive a fresh history projection', () {
    final timeline = TranscriptTimeline.project([
      {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'id': 'bridge',
            'function': {'name': 'tool_call', 'arguments': '{}'},
          },
        ],
        'tool_call_labels': {
          'bridge': [
            {
              'text': 'Calendar · Create event',
              'name': 'calendar.create_event',
              'preview': 'Lunch',
            },
          ],
        },
      },
      {'role': 'tool', 'tool_call_id': 'bridge', 'content': '{"success":true}'},
    ], presentationId: (_) => Object());
    final view = ToolCallPresentation.saved(timeline.entries.last.tool!);
    expect(view.title, 'Calendar · Create event');
    expect(view.target, 'Lunch');
    expect(view.durationSeconds, isNull);
  });

  test(
    'generation, replay and missed starts cannot create elapsed counters',
    () {
      final runtime = ChatRuntime(runtimeId: 'test');
      runtime.observeTool('tool.generating', {
        'name': 'web_search',
      }, receivedAt: Duration.zero);
      expect(runtime.observation.toolActivities, isEmpty);
      runtime.observeTool('tool.start', {
        'tool_id': 'replayed',
        'name': 'web_search',
      }, live: false);
      runtime.observeTool('tool.complete', {
        'tool_id': 'missed',
        'name': 'web_search',
        'duration_s': 2.4,
      });
      expect(
        runtime.observation.toolActivities.every(
          (tool) => tool.startedAt == null,
        ),
        isTrue,
      );
      expect(runtime.observation.toolActivities.last.durationSeconds, 2.4);
    },
  );

  test(
    'same-name parallel calls retain separate starts and terminal calls cannot regress',
    () {
      final runtime = ChatRuntime(runtimeId: 'test');
      for (final id in ['one', 'two']) {
        runtime.observeTool('tool.start', {
          'tool_id': id,
          'name': 'web_search',
        }, receivedAt: const Duration(seconds: 10));
      }
      runtime.observeTool('tool.start', {
        'tool_id': 'one',
        'name': 'web_search',
      }, receivedAt: const Duration(seconds: 12));
      expect(runtime.observation.toolActivities, hasLength(2));
      expect(
        runtime.observation.toolActivities.first.startedAt,
        const Duration(seconds: 10),
      );
      runtime.observeTool('tool.complete', {
        'tool_id': 'one',
        'name': 'web_search',
        'duration_s': 1.5,
      });
      runtime.observeTool('tool.start', {
        'tool_id': 'one',
        'name': 'web_search',
      }, receivedAt: const Duration(seconds: 14));
      expect(runtime.observation.toolActivities.first.isTerminal, isTrue);
      final view = ToolCallPresentation.live(
        runtime.observation.toolActivities.first,
      );
      expect(view.startedAt, isNull);
      expect(view.durationSeconds, 1.5);
      expect(runtime.observation.toolActivities.last.isTerminal, isFalse);
    },
  );
}
