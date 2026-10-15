import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/chat_runtime.dart';
import 'package:wing/core/models/gateway_activity.dart';
import 'package:wing/core/models/transcript_timeline.dart';
import 'package:wing/core/services/chat_runtime.dart' as execution;
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/profile_execution_activity.dart';
import 'package:wing/core/widgets/profile_activity_tabs.dart';
import 'package:wing/core/widgets/profile_live_execution.dart';
import 'package:wing/core/widgets/profile_tool_call.dart';
import 'package:wing/core/widgets/profile_tool_activity.dart';
import 'package:wing/core/widgets/tool_activity_details.dart';

import 'helpers/pump_markdown_widget.dart';

void main() {
  test('reasoning overlap requires exact call ownership and received text', () {
    final runtime = execution.ChatRuntime(runtimeId: 'reasoning-scope');
    runtime.beginTurn(submitting: false);
    runtime.observeReasoning('reasoning.delta', {'text': 'Streamed plan'});
    runtime.observeReasoning('reasoning.available', {'text': 'Saved summary'});
    runtime.observeTool('tool.start', {
      'tool_id': 'current',
      'name': 'read_file',
    });
    final matched = <String, dynamic>{
      'id': 1,
      'role': 'assistant',
      'content': '',
      'reasoning': 'Saved summary',
      'tool_calls': [
        {
          'id': 'current',
          'function': {'name': 'read_file', 'arguments': '{}'},
        },
      ],
    };
    final distinct = [
      {...matched, 'id': 2, 'reasoning': 'Unobserved saved reasoning'},
      {...matched, 'id': 3, 'content': 'A saved answer'},
      {...matched, 'id': 4, 'tool_calls': <Object>[]},
      {
        ...matched,
        'id': 5,
        'tool_calls': [
          {'id': 'earlier-turn'},
        ],
      },
      {
        ...matched,
        'id': 6,
        'tool_calls': [
          {'id': 'current'},
          {'id': 'unobserved'},
        ],
      },
    ];
    final projection = ChatTranscriptProjection(
      savedRows: [matched, ...distinct],
      streamingMessage: null,
      runtime: runtime.observation,
      presentationId: (row) => row['id']!,
      liveAnswering: true,
    );
    expect(projection.rows.map((row) => row['id']), [2, 3, 4, 5, 6]);
    expect(projection.activity, hasLength(2));
  });
  test('live history refresh does not replay reasoning before its tools', () {
    final runtime = execution.ChatRuntime(runtimeId: 'reasoning-receipts');
    runtime.beginTurn(submitting: false);
    final rows = <Map<String, dynamic>>[
      {'id': 1, 'role': 'user', 'content': 'Check both sources.'},
    ];
    for (var i = 0; i < 2; i++) {
      runtime.observeReasoning('reasoning.available', {'text': 'Plan $i'});
      runtime.observeTool('tool.complete', {
        'tool_id': 'call-$i',
        'name': 'read_file',
        'result': 'Result $i',
      });
      rows.addAll([
        {
          'id': 2 + i * 2,
          'role': 'assistant',
          'content': '',
          'reasoning': 'Plan $i',
          'tool_calls': [
            {
              'id': 'call-$i',
              'function': {'name': 'read_file', 'arguments': '{}'},
            },
          ],
        },
        {
          'id': 3 + i * 2,
          'role': 'tool',
          'tool_call_id': 'call-$i',
          'content': 'Result $i',
        },
      ]);
    }
    ChatTranscriptProjection project(bool live) => ChatTranscriptProjection(
      savedRows: rows,
      streamingMessage: null,
      runtime: runtime.observation,
      presentationId: (row) => row['id']!,
      liveAnswering: live,
    );
    final live = project(true);
    expect(live.rows.map((row) => row['id']), [1]);
    expect(live.activity, hasLength(4));
    expect(
      live.timeline.sections.where((section) => section.isActivity),
      isEmpty,
    );
    expect(rows, hasLength(5));
    final saved = project(false);
    expect(saved.rows, hasLength(5));
    expect(saved.timeline.sections.last.toolCount, 2);
  });
  test('live Activity association respects conversation boundaries', () {
    final work = <Map<String, dynamic>>[
      {'id': 1, 'role': 'user', 'content': 'Find local lunch.'},
      {
        'id': 2,
        'role': 'assistant',
        'content': '',
        'reasoning': 'Earlier reasoning',
      },
    ];
    TranscriptTimeline project(List<Map<String, dynamic>> rows, {int? live}) =>
        TranscriptTimeline.project(
          rows,
          presentationId: (row) => row['id']!,
          liveMessageIndex: live,
        );
    final pending = project(work);
    expect(pending.adjacentLiveActivity, same(pending.sections.last));
    final streaming = project([
      ...work,
      {'id': 3, 'role': 'assistant', 'content': 'Current answer'},
    ], live: 2);
    expect(
      streaming.adjacentLiveActivity,
      same(streaming.sections[streaming.sections.length - 2]),
    );
    expect(
      project([
        ...work,
        {'id': 3, 'role': 'user', 'content': 'A later question'},
        {'id': 4, 'role': 'assistant', 'content': 'A later answer'},
      ], live: 3).adjacentLiveActivity,
      isNull,
    );
    expect(
      project([
        ...work,
        {'id': 3, 'role': 'assistant', 'content': 'A saved answer'},
        {'id': 4, 'role': 'assistant', 'content': 'Another live answer'},
      ], live: 3).adjacentLiveActivity,
      isNull,
    );
    expect(
      project([
        ...work,
        {'id': 3, 'role': 'system', 'content': 'review: Memory updated'},
      ]).adjacentLiveActivity,
      isNull,
    );
    expect(work, hasLength(2));
  });
  ChatToolEntry tool(String id) => ChatToolEntry(
    GatewayToolActivity(
      toolId: id,
      name: 'read_file',
      phase: GatewayToolActivityPhase.completed,
      arguments: '{"path":"$id.md"}',
      result: '## Received $id\n\nExact received text.',
      durationSeconds: .4,
    ),
  );
  testWidgets(
    'reasoning is readable between independently collapsed tool runs',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileLiveExecution(
                entries: [
                  tool('first'),
                  const ChatReasoningEntry(
                    identity: 'plan',
                    text: 'Check the **received evidence**.',
                    source: 'reasoning.delta',
                    running: true,
                  ),
                  tool('second'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.settleMarkdown();
      expect(
        find.text('Check the received evidence.', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(ProfileReasoningDisclosure), findsNothing);
      expect(find.byType(ProfileToolCall, skipOffstage: false), findsNothing);
      expect(find.byType(ProfileActivitySection), findsNWidgets(2));
      final blocks = find.text('Activity · 1 tool');
      final reasoning = find.text(
        'Check the received evidence.',
        findRichText: true,
      );
      expect(
        tester.getTopLeft(blocks.first).dy,
        lessThan(tester.getTopLeft(reasoning).dy),
      );
      expect(
        tester.getTopLeft(reasoning).dy,
        lessThan(tester.getTopLeft(blocks.last).dy),
      );
      await tester.tap(blocks.first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ProfileToolCall>(find.byType(ProfileToolCall))
            .call
            .callId,
        'first',
      );
      expect(reasoning, findsOneWidget);
    },
  );
  testWidgets('current saved reasoning stays outside collapsed tool runs', (
    tester,
  ) async {
    final saved = TranscriptTimeline.project([
      {
        'id': 1,
        'role': 'tool',
        'tool_call_id': 'saved-one',
        'tool_name': 'read_file',
        'content': 'First result',
      },
      {
        'id': 2,
        'role': 'assistant',
        'content': '',
        'reasoning': 'Saved current reasoning',
      },
      {
        'id': 3,
        'role': 'tool',
        'tool_call_id': 'saved-two',
        'tool_name': 'read_file',
        'content': 'Second result',
      },
    ], presentationId: (row) => row['id']!).sections.single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileLiveExecution(
              savedActivity: saved,
              entries: [tool('live-three')],
            ),
          ),
        ),
      ),
    );
    await tester.settleMarkdown();
    expect(
      find.text('Saved current reasoning', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(ProfileReasoningDisclosure), findsNothing);
    expect(find.byType(ProfileActivitySection), findsNWidgets(2));
  });

  testWidgets('saved and live contiguous tools share one Activity disclosure', (
    tester,
  ) async {
    final saved = TranscriptTimeline.project([
      {
        'id': 1,
        'role': 'tool',
        'tool_call_id': 'saved-one',
        'tool_name': 'read_file',
        'content': 'First result',
      },
      {
        'id': 2,
        'role': 'tool',
        'tool_call_id': 'saved-two',
        'tool_name': 'read_file',
        'content': 'Second result',
      },
    ], presentationId: (row) => row['id']!).sections.single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileLiveExecution(
              savedActivity: saved,
              entries: [tool('live-three')],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProfileActivitySection), findsOneWidget);
    expect(find.text('Activity · 3 tools'), findsOneWidget);
    await tester.openLiveActivity();
    expect(find.byType(ProfileToolCall), findsNWidgets(3));
  });

  testWidgets('older saved receipts retain the opened live run', (
    tester,
  ) async {
    Widget view(List<int> ids) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProfileLiveExecution(
            savedActivity: TranscriptTimeline.project([
              for (final id in ids)
                {
                  'id': id,
                  'role': 'tool',
                  'tool_call_id': 'saved-$id',
                  'tool_name': 'read_file',
                  'content': 'Result $id',
                },
            ], presentationId: (row) => row['id']!).sections.single,
            entries: [tool('native')],
          ),
        ),
      ),
    );
    await tester.pumpWidget(view([2]));
    await tester.pumpAndSettle();
    await tester.openLiveActivity();
    await tester.pumpWidget(view([1, 2]));
    await tester.pumpAndSettle();
    expect(find.text('Activity · 3 tools'), findsOneWidget);
    expect(find.byType(ProfileToolCall), findsNWidgets(3));
  });

  for (final live in [true, false]) {
    testWidgets('only historical Activity assembles Agents tabs live=$live', (
      tester,
    ) async {
      final section = TranscriptTimeline.project([
        {
          'id': 1,
          'role': 'user',
          'display_kind': 'async_delegation_complete',
          'content': 'Agent result',
          'display_content': 'Subagent Task Completed',
        },
        if (!live)
          {
            'id': 2,
            'role': 'tool',
            'tool_call_id': 'call',
            'tool_name': 'read_file',
            'content': 'File result',
          },
      ], presentationId: (row) => row['id']!).sections.single;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: live
                  ? ProfileLiveExecution(
                      savedActivity: section,
                      entries: [tool('call')],
                    )
                  : ProfileToolActivitySection(
                      section: section,
                      noticeBuilder: (_) => const Text('Agent result'),
                    ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProfileActivitySection), findsOneWidget);
      await tester.tap(find.text('Activity · 1 tool'));
      await tester.pumpAndSettle();
      final tabs = tester.widget<ProfileActivityTabs>(
        find.byType(ProfileActivityTabs),
      );
      expect(
        tabs.tabs.map((tab) => tab.id),
        live ? ['timeline'] : ['timeline', 'agents'],
      );
      if (live) {
        expect(find.text('Agents'), findsNothing);
        expect(find.text('Agent result'), findsNothing);
        expect(find.byType(ProfileToolCall), findsOneWidget);
        return;
      }
      expect(find.byType(ProfileToolCall), findsOneWidget);
      await tester.tap(find.text('Agents'));
      await tester.pumpAndSettle();
      expect(find.text('Agent result'), findsOneWidget);
      expect(find.byType(ProfileToolCall), findsNothing);
      await tester.tap(find.text('Timeline'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileToolCall), findsOneWidget);
    });
  }

  testWidgets('current completion receipt alone creates no Activity', (
    tester,
  ) async {
    final section = TranscriptTimeline.project([
      {
        'id': 1,
        'role': 'user',
        'display_kind': 'async_delegation_complete',
        'content': 'Agent result',
        'display_content': 'Subagent Task Completed',
      },
    ], presentationId: (row) => row['id']!).sections.single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileLiveExecution(savedActivity: section, entries: const []),
        ),
      ),
    );
    expect(find.byType(ProfileActivitySection), findsNothing);
  });

  testWidgets('current saved tool receipts do not reconstruct dock categories', (
    tester,
  ) async {
    final section = TranscriptTimeline.project([
      {
        'id': 1,
        'role': 'tool',
        'tool_call_id': 'delegate',
        'tool_name': 'delegate_task',
        'content': '{"status":"dispatched","goals":["Research dinner"]}',
      },
      {
        'id': 2,
        'role': 'tool',
        'tool_call_id': 'todo',
        'tool_name': 'todo',
        'content':
            '{"revision":1,"todos":[{"id":"t1","content":"Check sources","status":"pending"}]}',
      },
    ], presentationId: (row) => row['id']!).sections.single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileLiveExecution(savedActivity: section, entries: const []),
        ),
      ),
    );
    await tester.openLiveActivity();
    final tabs = tester.widget<ProfileActivityTabs>(
      find.byType(ProfileActivityTabs),
    );
    expect(tabs.tabs.map((tab) => tab.id), ['timeline']);
    expect(find.byType(ProfileToolCall), findsNWidgets(2));
  });

  testWidgets('all 12 earlier tools remain visible beside 3 later calls', (
    tester,
  ) async {
    final runtime = execution.ChatRuntime(runtimeId: '12-plus-3');
    runtime.beginTurn(submitting: false);
    void complete(int index) => runtime.observeTool('tool.complete', {
      'tool_id': 'call-$index',
      'name': 'read_file',
      'result': 'Result $index',
    });
    for (var i = 0; i < 12; i++) {
      complete(i);
    }
    runtime.observeReasoning('reasoning.available', {
      'text': 'Check the remaining three sources.',
    });
    for (var i = 12; i < 15; i++) {
      complete(i);
    }
    expect(runtime.observation.execution, ChatExecution.running);
    expect(
      runtime.observation.activityEntries.whereType<ChatToolEntry>(),
      hasLength(15),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileLiveExecution(
              entries: runtime.observation.activityEntries,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.openLiveActivity();
    expect(find.byType(ProfileToolCall), findsNWidgets(15));
    expect(
      tester
          .widgetList<ProfileToolCall>(find.byType(ProfileToolCall))
          .map((call) => call.call.callId),
      [for (var i = 0; i < 15; i++) 'call-$i'],
    );
    expect(find.text('Activity · 12 tools'), findsOneWidget);
    expect(find.byType(ProfileActivitySection), findsNWidgets(2));
  });
  testWidgets('one live reply keeps every completed cycle readable', (
    tester,
  ) async {
    final runtime = execution.ChatRuntime(runtimeId: 'repeated-cycles');
    runtime.beginTurn(submitting: false);
    runtime.observeReasoning('reasoning.available', {
      'text': 'First reasoning',
    });
    runtime.observeTool('tool.complete', {
      'tool_id': 'one',
      'name': 'read_file',
      'result': 'First result',
    });
    runtime.observeReasoning('reasoning.available', {
      'text': 'Second reasoning',
    });
    runtime.observeTool('tool.start', {'tool_id': 'two', 'name': 'web_search'});
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileLiveExecution(
              entries: runtime.observation.activityEntries,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.openLiveActivity();
    expect(find.byType(ProfileActivitySection), findsNWidgets(2));
    expect(find.text('Activity'), findsNothing);
    expect(find.text('Activity · 1 tool'), findsNWidgets(2));
    expect(find.text('Timeline'), findsNWidgets(2));
    await tester.settleMarkdown();
    expect(find.text('First reasoning', findRichText: true), findsOneWidget);
    expect(find.text('Second reasoning', findRichText: true), findsOneWidget);
    expect(find.byType(ProfileReasoningDisclosure), findsNothing);
    expect(find.byType(ProfileToolCall), findsNWidgets(2));
  });
  testWidgets(
    'tool-only live run starts collapsed and retains cards after opening',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: Scaffold(body: ProfileLiveExecution(entries: [tool('first')])),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Timeline'), findsNothing);
      expect(find.byType(ProfileToolCall, skipOffstage: false), findsNothing);
      expect(find.text('Activity · 1 tool'), findsOneWidget);
      await tester.openLiveActivity();
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.byType(ProfileToolCall), findsOneWidget);
      final original = tester.element(find.byType(ProfileToolCall));
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: Scaffold(
            body: ProfileLiveExecution(
              entries: [
                tool('first'),
                const ChatReasoningEntry(
                  identity: 'empty',
                  text: ' \n ',
                  source: 'reasoning.available',
                ),
                tool('second'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.openLiveActivity();
      expect(find.byType(ProfileActivitySection), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.byType(ProfileToolCall), findsNWidgets(2));
      expect(
        tester.element(find.byType(ProfileToolCall).first),
        same(original),
      );
    },
  );
  testWidgets('completed reasoning remains readable during a live turn', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileLiveExecution(
              entries: [
                ChatReasoningEntry(
                  identity: 'reasoning',
                  text:
                      '## Searching for Tokyo hotels\n\nCheck the booking pages.',
                  source: 'reasoning.available',
                  running: false,
                ),
                tool('first'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.openLiveActivity();
    await tester.settleMarkdown();
    expect(
      find.text('Searching for Tokyo hotels', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Reasoning'), findsOneWidget);
    expect(find.byType(ProfileActivitySection), findsOneWidget);
    expect(find.byType(ProfileReasoningDisclosure), findsNothing);
  });
  testWidgets('live reasoning cycles retain expanded tools', (tester) async {
    final firstReasoning = const ChatReasoningEntry(
      identity: 'first-reasoning',
      text: 'Check local lunch options.',
      source: 'reasoning.available',
    );
    Future<void> show(List<ChatActivityEntry> entries) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileLiveExecution(entries: entries),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.openLiveActivity();
    }

    await show([firstReasoning, tool('first')]);
    final original = tester.element(find.byType(ProfileToolCall));
    await tester.tap(find.text('Read file'));
    await tester.pumpAndSettle();
    await tester.openLiveActivity();
    expect(find.byType(ToolActivityDetailsView), findsOneWidget);
    await show([
      firstReasoning,
      tool('first'),
      const ChatReasoningEntry(
        identity: 'second-reasoning',
        text: 'Confirm the restaurant hours.',
        source: 'reasoning.available',
      ),
      tool('second'),
    ]);
    expect(find.byType(ProfileActivitySection), findsNWidgets(2));
    expect(find.byType(ProfileReasoningDisclosure), findsNothing);
    expect(find.byType(ToolActivityDetailsView), findsOneWidget);
    expect(
      tester.element(
        find.byWidgetPredicate(
          (widget) =>
              widget is ProfileToolCall && widget.call.callId == 'first',
        ),
      ),
      same(original),
    );
  });
  testWidgets('reasoning remains readable while the turn remains running', (
    tester,
  ) async {
    final runtime = execution.ChatRuntime(runtimeId: 'handoff');
    runtime.beginTurn(submitting: false);
    runtime.observeReasoning('reasoning.delta', {
      'text': '## Searching for Tokyo hotels\n\nCheck the booking pages.',
    });
    Future<void> show() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileLiveExecution(
                entries: runtime.observation.activityEntries,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.openLiveActivity();
      await tester.settleMarkdown();
    }

    await show();
    expect(find.text('Thinking'), findsOneWidget);
    expect(
      find.text('Searching for Tokyo hotels', findRichText: true),
      findsOneWidget,
    );
    runtime.observeTool('tool.start', {
      'tool_id': 'booking',
      'name': 'read_file',
    });
    expect(runtime.observation.execution, ChatExecution.running);
    expect(
      (runtime.observation.activityEntries.first as ChatReasoningEntry).running,
      isFalse,
    );
    await show();
    expect(
      find.text('Searching for Tokyo hotels', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.byType(ProfileToolCall), findsOneWidget);
    expect(find.byType(ProfileActivitySection), findsOneWidget);
    runtime.observeTool('tool.complete', {
      'tool_id': 'booking',
      'name': 'read_file',
      'result': 'Booking pages',
    });
    runtime.observeReasoning('reasoning.available', {
      'text': 'Confirm the cancellation policy.',
    });
    runtime.observeTool('tool.start', {
      'tool_id': 'policy',
      'name': 'web_search',
    });
    runtime.reconcileHistoricalActivity();
    await show();
    expect(runtime.observation.execution, ChatExecution.running);
    expect(
      find.text('Searching for Tokyo hotels', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Confirm the cancellation policy.', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(ProfileActivitySection), findsNWidgets(2));
  });
  testWidgets(
    'live segmentation retains existing tool cards and expansion state',
    (tester) async {
      final first = tool('first');
      Future<void> show(List<ChatActivityEntry> entries) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(Brightness.dark),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ProfileLiveExecution(entries: entries),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.openLiveActivity();
        await tester.settleMarkdown();
      }

      await show([first]);
      final original = tester.element(find.byType(ProfileToolCall));
      final retained = original.widget as ProfileToolCall;
      expect(retained.call.callId, 'first');
      await tester.tap(find.text('Read file'));
      await tester.pumpAndSettle();
      await tester.openLiveActivity();
      await tester.settleMarkdown();
      final output = find.byType(ToolActivityDetailsView);
      expect(output, findsOneWidget);
      final reasoning = ChatReasoningEntry(
        identity: 'reasoning',
        text: '## Why\n\nKeep the **useful details** visible.',
        source: 'reasoning.delta',
        running: true,
      );
      await show([first, reasoning, tool('second')]);
      expect(find.byType(ProfileReasoningDisclosure), findsNothing);
      expect(find.byType(ProfileActivitySection), findsNWidgets(2));
      expect(find.text('Timeline'), findsNWidgets(2));
      expect(find.byType(ProfileActivityGuide), findsNWidgets(2));
      for (final tabs in tester.widgetList<ProfileActivityTabs>(
        find.byType(ProfileActivityTabs),
      )) {
        expect(tabs.tabs.single.id, 'timeline');
      }
      final firstCard = find.byWidgetPredicate(
        (w) => w is ProfileToolCall && w.call.callId == 'first',
      );
      expect(tester.element(firstCard), same(original));
      expect(output, findsOneWidget);
      expect(
        tester.getTopLeft(firstCard).dy,
        lessThan(tester.getTopLeft(find.text('Why', findRichText: true)).dy),
      );
      final secondCard = find.byWidgetPredicate(
        (w) => w is ProfileToolCall && w.call.callId == 'second',
      );
      expect(
        tester.getTopLeft(find.text('Why', findRichText: true)).dy,
        lessThan(tester.getTopLeft(secondCard).dy),
      );
      expect((tester.widget<ProfileToolCall>(firstCard)).call.callId, 'first');
      await show([first, reasoning.sealed(), tool('second')]);
      expect(find.text('Why', findRichText: true), findsOneWidget);
      expect(find.byType(ProfileReasoningDisclosure), findsNothing);
      expect(tester.element(firstCard), same(original));
      expect(output, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'history reconciliation retains live ordering until the turn retires',
    () {
      final runtime = execution.ChatRuntime(runtimeId: 'live');
      runtime.beginTurn(submitting: false);
      runtime.observeTool('tool.start', {
        'tool_id': 'one',
        'name': 'read_file',
      });
      runtime.observeTool('tool.complete', {
        'tool_id': 'one',
        'name': 'read_file',
        'result': 'Original output',
      });
      runtime.observeReasoning('reasoning.available', {
        'text': 'Original reasoning',
      });
      runtime.reconcileHistoricalActivity();
      expect(runtime.observation.activityEntries, hasLength(2));
      expect(
        (runtime.observation.activityEntries.first as ChatToolEntry)
            .activity
            .result,
        'Original output',
      );
      runtime.observeExecutionSnapshot({'running': false});
      runtime.reconcileHistoricalActivity();
      expect(runtime.observation.activityEntries, isEmpty);
    },
  );
}
