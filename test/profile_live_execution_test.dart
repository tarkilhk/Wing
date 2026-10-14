import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/chat_runtime.dart';
import 'package:wing/core/models/gateway_activity.dart';
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
  testWidgets('tool-only live run has no intermediary Activity row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: Scaffold(body: ProfileLiveExecution(entries: [tool('first')])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Activity · 1 tool'), findsNothing);
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
    expect(find.byType(ProfileActivitySection), findsNothing);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.byType(ProfileToolCall), findsNWidgets(2));
    expect(tester.element(find.byType(ProfileToolCall).first), same(original));
  });
  testWidgets('completed live reasoning is contained in Activity', (
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
    await tester.settleMarkdown();
    expect(
      find.text('Searching for Tokyo hotels', findRichText: true),
      findsNothing,
    );
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileReasoningDisclosure), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(ProfileReasoningDisclosure),
        matching: find.byType(ProfileActivitySection),
      ),
      findsOneWidget,
    );
  });
  testWidgets('tool handoff folds reasoning while the turn remains running', (
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
      findsNothing,
    );
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.byType(ProfileToolCall), findsOneWidget);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileReasoningDisclosure), findsOneWidget);
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
        await tester.settleMarkdown();
      }

      await show([first]);
      final original = tester.element(find.byType(ProfileToolCall));
      final retained = original.widget as ProfileToolCall;
      expect(retained.call.callId, 'first');
      await tester.tap(find.text('Read file'));
      await tester.pumpAndSettle();
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
      expect(find.byType(ProfileActivitySection), findsOneWidget);
      final activity = find.text('Activity · 1 tool');
      await tester.tap(activity.first);
      await tester.pumpAndSettle();
      await tester.settleMarkdown();
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
      expect(find.text('Why', findRichText: true), findsNothing);
      expect(find.byType(ProfileReasoningDisclosure), findsOneWidget);
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
