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
  test('activity requests and receipts preserve current stock tool facts', () {
    const diff = '--- a/report.py\n+++ b/report.py\n@@ -1 +1 @@\n-old\n+new';
    final patch = completed(
      'patch',
      {'success': true, 'diff': diff},
      args: {
        'path': '/workspace/report.py',
        'old_string': 'old',
        'new_string': '',
      },
    ).activityDetails;
    expect(patch.resourceTarget, '/workspace/report.py');
    expect(patch.request.map((b) => b.text), ['old', '']);
    expect(patch.response.single.label, 'Reported diff');
    expect(patch.response.single.text, diff);
    final failed = completed(
      'patch',
      {'error': 'No match found'},
      args: {
        'path': '/workspace/report.py',
        'old_string': 'old',
        'new_string': 'new',
      },
    );
    expect(failed.outcome, ToolCallOutcome.error);
    expect(failed.activityDetails.response.map((b) => b.label), ['Error']);
    final write = completed(
      'write_file',
      {'bytes_written': 4, 'verified': true},
      args: {'path': '/workspace/report.py', 'content': 'new\n'},
    );
    expect(write.activityDetails.request.single.text, 'new\n');
    expect(write.activityDetails.metadata, ['Content hash verified']);
    expect(write.activityDetails.response, isEmpty);
    expect(write.outcome, ToolCallOutcome.success);
  });

  test(
    'file receipts and console output keep exact text and reported limits',
    () {
      const content = '21|# Heading\n22|  **literal**\n';
      final read = completed(
        'read_file',
        {
          'content': content,
          'total_lines': 80,
          'file_size': 912,
          'truncated': true,
          'next_offset': 23,
        },
        args: {'path': '/workspace/report.py', 'offset': 21, 'limit': 2},
      ).activityDetails;
      expect(read.response.single.text, content);
      expect(read.request, isEmpty);
      expect(read.headerFacts, ['Offset: 21', 'Limit: 2']);
      expect(
        read.resourceFor('/workspace/report.py')?.path,
        '/workspace/report.py',
      );
      expect(read.resourceFor('javascript:alert(1)'), isNull);
      expect(read.resourceFor('data:image/png;base64,AA=='), isNull);
      expect(read.resourceFor('https://user:password@example.org/x'), isNull);
      expect(read.response.single.numberedLines, isTrue);
      expect(read.response.single.markdown, isFalse);
      const numberedMarkdown = '21|# Report\n22|\n23|**Ready**';
      final markdownRead = completed(
        'read_file',
        {'content': numberedMarkdown},
        args: {'path': '/workspace/report.md', 'offset': 21, 'limit': 3},
      ).activityDetails.response.single;
      expect(markdownRead.label, 'Result');
      expect(markdownRead.markdown, isTrue);
      expect(markdownRead.documentText, '# Report\n\n**Ready**');
      expect(markdownRead.text, numberedMarkdown);
      expect(read.metadata, [
        'Total lines: 80',
        'Partial file returned',
        'Next offset: 23',
      ]);
      final code = completed(
        'execute_code',
        {'output': '**literal**\n  exact\n', 'status': 'success'},
        args: {'code': 'print("exact")'},
      ).activityDetails;
      expect(code.response.single.markdown, isFalse);
      expect(code.response.single.text, '**literal**\n  exact\n');
      expect(code.exitCode, isNull);
      expect(
        completed('terminal', {
          'exit_code': 2,
          'stdout': '',
        }).activityDetails.exitCode,
        2,
      );
      expect(
        completed('read_file', {
          'content': '',
          'total_lines': 0,
        }).activityDetails.response.single.text,
        '',
      );
    },
  );

  test('native vision is an image receipt rather than invented analysis', () {
    final receipt = completed(
      'vision_analyze',
      {
        '_multimodal': true,
        'content': [
          {'type': 'text', 'text': 'Image loaded into your context.'},
        ],
        'text_summary': 'Image loaded',
        'meta': {'native_vision': true},
      },
      args: {
        'image_url': '/workspace/dashboard.png',
        'question': 'Check legibility',
      },
    ).activityDetails;
    expect(receipt.nativeVision, isTrue);
    expect(receipt.images.single.target, '/workspace/dashboard.png');
    expect(receipt.request.single.text, 'Check legibility');
    expect(receipt.response, isEmpty);
    expect(receipt.receiptStatus, isNull);
    expect(receipt.response.any((b) => b.label == 'Analysis'), isFalse);
    final generated = completed('image_generate', {
      'image': '/workspace/generated.png',
    }).activityDetails;
    expect(generated.images.single.target, '/workspace/generated.png');
  });

  test('search counts retain the stock lower-bound qualification', () {
    for (final lowerBound in [true, false, null]) {
      final search = completed('search_files', {
        'total_count': 250,
        'truncated': true,
        'total_count_is_lower_bound': ?lowerBound,
      }).activityDetails;
      expect(
        search.metadata,
        contains(
          lowerBound == true
              ? 'Reported rows: at least 250'
              : 'Reported rows: 250',
        ),
      );
      expect(search.metadata, contains('Partial results returned'));
      expect(
        search.metadata.where((fact) => fact.startsWith('Reported rows:')),
        hasLength(1),
      );
    }
  });

  test('structured search and unknown tool data remain readable', () {
    final search = completed(
      'search_files',
      {
        'matches': [
          {'path': 'report.py', 'line': 9, 'content': 'hello'},
        ],
        'total_count': 1,
        'truncated': false,
      },
      args: {'pattern': 'hello'},
    ).activityDetails;
    expect(search.request.single.text, 'hello');
    expect(search.metadata, ['Reported rows: 1']);
    expect(search.response.single.text, '9|hello');
    expect(search.response.single.copyText, 'hello');
    final other = completed(
      'connector_query',
      {
        'message': 'Returned data',
        'records': [
          {'name': 'Example', 'count': 3},
        ],
      },
      args: {
        'filter': {'region': 'north'},
        'limit': 3,
      },
    ).activityDetails;
    expect(other.request, isEmpty);
    expect(other.headerFacts, isEmpty);
    expect(other.response.single.text, 'Returned data');
    expect(other.response.single.copyable, isFalse);
  });

  test('file checks stay independent and diagnostics appear exactly once', () {
    for (final name in ['write_file', 'patch']) {
      final receipt = completed(name, {
        'lint': {
          'status': 'skipped',
          'message': 'No syntax checker configured',
        },
        'lsp_diagnostics': 'report.py:9: unresolved name',
      }).activityDetails;
      expect(receipt.metadata, isEmpty);
      expect(
        receipt.response.where(
          (block) => block.text == 'report.py:9: unresolved name',
        ),
        hasLength(1),
      );
      expect(
        receipt.response
            .singleWhere((block) => block.label == 'Semantic diagnostics')
            .text,
        'report.py:9: unresolved name',
      );
      expect(receipt.metadata, isNot(contains('Write verified by server')));
    }
  });

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
        'Read mileage; see example.org/docs',
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
        'Open preview · example.org/map',
      ),
      (
        'drive_preview',
        {'action': 'click', 'ref': 'button-12'},
        'Click button-12',
      ),
      (
        'tool_describe',
        {
          'names': ['session_search', 'mcp__tracker__lookup'],
        },
        'Session search · Lookup',
      ),
      (
        'search_files',
        {'pattern': 'mileage', 'path': 'trip/sources'},
        'mileage · sources',
      ),
      ('read_file', {'path': 'trip/items.json'}, 'items.json'),
      ('skill_view', {'name': 'hermes-agent'}, 'hermes-agent'),
      (
        'execute_code',
        {'code': '# Compare rental prices\nprint(prices)'},
        '# Compare rental prices print(prices)',
      ),
      (
        'hindsight_retain',
        {'content': 'Remember the booking\nand cancellation deadline.'},
        'Remember the booking and cancellation deadline.',
      ),
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
      final call = completed(name, {}, args: args);
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
  test(
    'semantic intent subtitles normalize multiline input and preserve exact evidence',
    () {
      const query = 'gmail\n fetch emails';
      final search = completed(
        'tool_search',
        {
          'results': [
            {'query': query, 'matches': <String>[]},
          ],
          'tools': <String, Object?>{},
        },
        args: {
          'queries': [query],
        },
      );
      expect(search.subtitle, 'gmail fetch emails');
      expect(search.activityDetails.request.single.text, query);
      expect(search.arguments, contains(r'\n'));
      final question = completed(
        'clarify',
        {
          'responses': [
            {
              'question': 'Which report?\nChoose a format.',
              'choices_offered': ['Markdown', 'Text'],
              'status': 'answered',
              'user_response': 'Markdown',
            },
          ],
          'outcome': 'submitted',
        },
        args: {
          'questions': [
            {
              'question': 'Which report?\nChoose a format.',
              'choices': ['Markdown', 'Text'],
            },
          ],
        },
      );
      expect(question.subtitle, 'Which report? Choose a format.');
      expect(
        question.activityDetails.request.first.text,
        'Which report?\nChoose a format.',
      );
    },
  );

  test('skill batch shows supplied skill intent and a quiet actual result', () {
    const raw =
        '{"success":true,"operations_applied":1,"results":['
        '{"name":"business-trip-policy-research","action":"patch",'
        '"file_path":"references/accommodation-search-quality.md","success":true}]}';
    final args = {
      'operations': [
        {
          'name': 'business-trip-policy-research',
          'action': 'patch',
          'file_path': 'references/accommodation-search-quality.md',
          'old_string': 'Old requirement',
          'new_string': 'New requirement',
        },
      ],
    };
    for (final call in [
      completed('skill_manage', raw, args: args),
      ToolCallPresentation.saved(
        TranscriptToolResult.fromRow({
          'role': 'tool',
          'tool_name': 'skill_manage',
          'content': raw,
          'args': args,
        }),
      ),
    ]) {
      final receipt = call.activityDetails;
      expect(receipt.response, isEmpty);
      expect(receipt.metadata, ['Operations applied: 1']);
      expect(call.result, raw);
    }
    final requests = completed(
      'skill_manage',
      raw,
      args: args,
    ).activityDetails.request;
    expect(requests.map((block) => block.label), [
      'business-trip-policy-research',
      'Replace with',
    ]);
    expect(requests.map((block) => block.text), [
      'Old requirement',
      'New requirement',
    ]);
    expect(requests.every((block) => block.copyable), isTrue);
    expect(requests.first.facts, [
      'Find',
      'patch',
      'references/accommodation-search-quality.md',
    ]);
  });

  test(
    'results keep actual errors and skip blank or routine operation facts',
    () {
      const failure =
          "operations[1] (write_file on 'policy') failed: Permission denied — batch aborted, rollback completed.";
      final call = completed('skill_manage', {
        'success': false,
        'error': failure,
        'failed_index': 1,
        'completed_before_failure': 1,
      });
      expect(call.activityDetails.response, hasLength(1));
      final error = call.activityDetails.response.single;
      expect(error.label, 'Error');
      expect(error.text, failure);
      expect(error.copyable, isFalse);
      expect(call.activityDetails.metadata, [
        'Failed operation: 2',
        'Operations attempted before failure: 1',
      ]);
      expect(
        completed('tool_call', {
          'content': [
            {'type': 'text', 'text': ' \n '},
          ],
        }).activityDetails.response,
        isEmpty,
      );
    },
  );

  test('search intent options are quiet and dense receipts group by file', () {
    const dense =
        'references/quality.md\n  16: First exact excerpt\n'
        '  19:   Keep leading indent\nreport.md\n  7: Last excerpt';
    final call = completed(
      'search_files',
      {
        'total_count': 3,
        'matches_text': dense,
        'matches_format':
            "path-grouped: each file path on its own line, followed by indented '<line>: <content>' rows for matches in that file",
        'truncated': true,
        'total_count_is_lower_bound': true,
      },
      args: {
        'pattern': 'quality|report',
        'path': '.',
        'target': 'content',
        'limit': 3,
        'context': 2,
        'output_mode': 'content',
      },
    );
    final receipt = call.activityDetails;
    expect(receipt.request.single.label, 'Pattern');
    expect(receipt.request.single.text, 'quality|report');
    expect(receipt.request.single.copyable, isTrue);
    expect(receipt.headerFacts, [
      'Target: content',
      'Limit: 3',
      'Output: content',
      'Context: 2',
    ]);
    expect(receipt.response, hasLength(2));
    expect(receipt.response.first.resourceTarget, 'references/quality.md');
    expect(
      receipt.response.first.text,
      '16|First exact excerpt\n19|  Keep leading indent',
    );
    expect(
      receipt.response.first.copyText,
      '  16: First exact excerpt\n  19:   Keep leading indent',
    );
    expect(receipt.response.last.resourceTarget, 'report.md');
    expect(receipt.metadata, [
      'Reported rows: at least 3',
      'Partial results returned',
    ]);
    expect(call.result, contains(dense.replaceAll('\n', r'\n')));
  });

  test(
    'write keeps content and real diagnostics while routine receipt stays raw',
    () {
      final call = completed(
        'write_file',
        {
          'path': '/resolved/report.md',
          'bytes_written': 48,
          'verified': true,
          'dirs_created': true,
          'lint': {'status': 'skipped', 'message': 'No linter for .md'},
          'lsp_diagnostics': 'report.md:9: unresolved reference',
        },
        args: {'path': 'report.md', 'content': '# Exact requested content'},
      );
      final receipt = call.activityDetails;
      expect(receipt.resourceTarget, 'report.md');
      expect(receipt.request.single.text, '# Exact requested content');
      expect(receipt.metadata, ['Content hash verified']);
      expect(receipt.response.single.label, 'Semantic diagnostics');
      expect(receipt.response.single.copyable, isFalse);
      expect(call.result, contains('No linter for .md'));
      expect(call.result, contains('dirs_created'));
      final failedCheck = completed('patch', {
        'lint': {'status': 'error', 'output': 'report.py:7: invalid syntax'},
        '_warning': 'Some edits could not be verified',
      }).activityDetails;
      expect(failedCheck.metadata, isEmpty);
      expect(failedCheck.response.map((b) => b.text), [
        'Syntax check failed.',
        'report.py:7: invalid syntax',
        'Some edits could not be verified',
      ]);
    },
  );

  test('terminal controls are quiet and literal output remains reusable', () {
    final call = completed(
      'terminal',
      {
        'output': 'exact\n  indented',
        'exit_code': 0,
        'truncation_note': 'Output truncated by server',
        'meta': {'transport': 'shell'},
      },
      args: {
        'command': 'python report.py',
        'timeout': 120,
        'workdir': '/workspace',
      },
    );
    expect(call.activityDetails.request.single.text, 'python report.py');
    expect(call.activityDetails.headerFacts, [
      'Directory: /workspace',
      'Timeout: 120',
    ]);
    expect(call.activityDetails.response.first.text, 'exact\n  indented');
    expect(call.activityDetails.response.first.copyable, isTrue);
    expect(
      call.activityDetails.response.last.text,
      'Output truncated by server',
    );
    expect(call.activityDetails.response.last.copyable, isFalse);
    expect(call.activityDetails.metadata, isEmpty);
  });

  test('unknown connector retains substance and raw technical fields', () {
    final call = completed(
      'connector_query',
      {
        'success': true,
        'message': 'Returned data',
        'records': [
          {'name': 'Example', 'count': 3},
        ],
        'metadata': {'schema_version': 4},
        '_transport': {'request_id': 'secret'},
      },
      args: {
        'filter': {'region': 'north'},
        'limit': 3,
      },
    );
    expect(call.activityDetails.headerFacts, isEmpty);
    expect(call.activityDetails.request, isEmpty);
    expect(call.activityDetails.response.single.text, 'Returned data');
    expect(call.activityDetails.response.single.copyable, isFalse);
    expect(call.result, contains('Example'));
    expect(call.result, contains('schema_version'));
    expect(call.result, contains('_transport'));
  });

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
        'Unchanged',
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
      final bridge = completed(
        'tool_call',
        {
          'results': [
            {
              'index': 0,
              'name': 'connectors__calendar__CREATE_EVENT',
              'error': {
                'code': 'PROVIDER_ERROR',
                'message': 'The event could not be created.',
              },
            },
          ],
          'success_count': 0,
          'error_count': 1,
          'total_count': 1,
        },
        args: {
          'calls': [
            {
              'name': 'connectors__calendar__CREATE_EVENT',
              'arguments': {'title': 'Lunch'},
            },
          ],
        },
      );
      expect(bridge.outcome, ToolCallOutcome.error);
      expect(
        bridge.activityDetails.response.single.text,
        'The event could not be created.',
      );
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
      expect(search.activityDetails.response.single.label, 'Mileage FAQ');
      expect(
        search.activityDetails.response.single.text,
        contains('Unlimited mileage'),
      );
    },
  );

  test('command output preserves indentation and literal Markdown markers', () {
    const stdout =
        '[Open source](https://example.org/literal)\n\n- option\n  indented\n\n';
    final call = completed('terminal', {'output': stdout, 'exit_code': 0});
    expect(call.activityDetails.response.single.text, stdout);
    expect(call.activityDetails.response.single.markdown, isFalse);
    expect(call.activityDetails.response.single.link, isNull);
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
      expect(
        call.activityDetails.response.single.text,
        contains('Unlimited mileage'),
      );
      expect(
        call.activityDetails.response.single.text,
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
      expect(view.activityDetails.images.single.target, '/tmp/map.png');
      expect(view.activityDetails.request.single.label, 'Question');
      expect(view.activityDetails.request.single.text, 'Which area?');
      expect(view.activityDetails.response.last.text, 'Yellow area');
      expect(
        ToolCallPresentation.saved(
          timeline.entries[2].tool!,
        ).activityDetails.images,
        isEmpty,
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
