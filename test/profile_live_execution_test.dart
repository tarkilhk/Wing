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
      final reasoning = ChatReasoningEntry(
        identity: 'reasoning',
        text: '## Why\n\nKeep the **useful details** visible.',
        source: 'reasoning.delta',
        running: true,
      );
      await show([first, reasoning, tool('second')]);
      expect(find.byType(ProfileReasoningDisclosure), findsNothing);
      expect(find.byType(ProfileActivitySection), findsNWidgets(2));
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
