import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/answer_versions.dart';
import 'package:hermes_android/core/models/transcript_notice.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/widgets/profile_message.dart';
import 'package:hermes_android/core/widgets/chat_find_sheet.dart';
import 'package:hermes_android/core/services/profile_gateway.dart';
import 'package:hermes_android/core/widgets/profile_tool_activity.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_history_fixture.dart';

const _envelope =
    '[ASYNC DELEGATION BATCH COMPLETE — deleg_be8ac8e4]\n'
    'A background fan-out unit you dispatched earlier has finished.\n'
    'Private instructions for the agent.\nRole: leaf  Model: gpt-5.6-terra\n\n'
    '--- ✓ TASK 1/2: private goal  (status=completed) ---\n'
    'First useful result\n'
    'Full live transcript (complete tool/assistant trace): /private/path\n\n'
    '--- ✓ TASK 2/2: private goal\nprivate continuation  (status=completed) ---\n'
    'Second useful result';

Map<String, dynamic> _notice() => {
  'id': 3,
  'role': 'user',
  'content': _envelope,
  'display_kind': 'async_delegation_complete',
  'display_metadata': {'task_count': 3},
};

class _NoticeHistory extends ProfileHistoryFixture {
  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    {'id': 1, 'role': 'user', 'content': 'Compare the options'},
    {'id': 2, 'role': 'assistant', 'content': 'Nothing is booked.'},
    _notice(),
    {
      'id': 4,
      'role': 'user',
      'content': 'Private hidden instructions',
      'display_kind': 'hidden',
    },
  ];
}

void main() {
  for (final width in [360.0, 900.0]) {
    testWidgets('typed delegation is a notice at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final row = _notice();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProfileMessage(message: row)),
        ),
      );
      expect(find.text(_envelope), findsNothing);
      expect(find.byTooltip('Copy message'), findsNothing);
      expect(isAnswerPrompt(row), isFalse);
      expect(find.text('3 background agents finished'), findsOneWidget);
      expect(find.text('First useful result'), findsNothing);
      await tester.tap(find.text('View result'));
      await tester.pumpAndSettle();
      expect(find.textContaining('First useful result'), findsOneWidget);
      expect(find.textContaining('Private instructions'), findsNothing);
      expect(find.textContaining('private goal'), findsNothing);
      expect(find.textContaining('Full live transcript'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'saved history and refresh preserve notices and hide scaffolding',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final host = _NoticeHistory();
      final controller = ProfileWorkspaceController(
        connection: identityTestConnection(),
        connectionIdentity: 'notice-history',
        preferences: await SharedPreferences.getInstance(),
        gatewayFactory: host.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final chat = ProfileChat(
        key: ProfileSessionKey(controller.current!.scope, 'chat-0'),
        runtimeId: '',
        title: 'Notice history',
      );
      controller.current!.chats['chat-0'] = chat;
      controller.current!.selectedSession = 'chat-0';
      await controller.refreshHistory(chat);
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      for (var refresh = 0; refresh < 2; refresh++) {
        expect(find.text(_envelope), findsNothing);
        expect(find.text('Private hidden instructions'), findsNothing);
        expect(find.text('3 background agents finished'), findsOneWidget);
        expect(find.byKey(const ValueKey('edit-message-3')), findsNothing);
        expect(find.byKey(const ValueKey('edit-message-1')), findsOneWidget);
        // Retain server history and IDs for paging/rewind; filter only the view.
        expect(chat.messages.map((row) => row['id']), [1, 2, 3, 4]);
        await controller.refreshHistory(chat);
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('Find in chat uses typed display text, not internal payloads', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatFindSheet(
          loadHistory: (_) async => ProfileHistoryPage(
            'chat',
            _NoticeHistory().historyRows('default', 'chat'),
            0,
            500,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Private');
    await tester.pump();
    expect(find.textContaining('Private instructions'), findsNothing);
    expect(find.textContaining('Private hidden'), findsNothing);
    expect(find.text('View in chat'), findsNothing);
    await tester.enterText(find.byType(TextField), 'First useful result');
    await tester.pump();
    expect(find.textContaining('First useful result'), findsWidgets);
    expect(find.text('1 matching message'), findsOneWidget);
    expect(find.text('system'), findsOneWidget);
  });

  test('hidden rows do not split tool groups or become prompts', () {
    final hidden = {
      'id': 2,
      'role': 'user',
      'content': 'private',
      'display_kind': 'hidden',
    };
    final sections = groupTranscriptSections([
      {'id': 1, 'role': 'tool', 'content': 'first'},
      hidden,
      {'id': 3, 'role': 'tool', 'content': 'second'},
    ]);
    expect(sections, hasLength(1));
    expect(sections.single.messages.map((row) => row['id']), [1, 3]);
    expect(isAnswerPrompt(hidden), isFalse);
  });

  test(
    'metadata accepts decoded and REST JSON values without leaking raw text',
    () {
      for (final metadata in [
        null,
        '{invalid',
        '[]',
        5,
        {'task_count': 'three'},
      ]) {
        expect(
          transcriptNoticeText({..._notice(), 'display_metadata': metadata}),
          'Background agent work finished',
        );
      }
      expect(
        transcriptNoticeText({
          ..._notice(),
          'display_metadata': '{"task_count":1}',
        }),
        '1 background agent finished',
      );
      for (final entry in {
        'model_switch': 'Model changed',
        'personality_switch': 'Personality changed',
        'auto_continue': 'Resumed interrupted turn',
      }.entries) {
        expect(
          transcriptNoticeText({
            'display_kind': entry.key,
            'content': 'private',
          }),
          entry.value,
        );
      }
    },
  );

  test('single, batch, cron and malformed results use producer boundaries', () {
    expect(
      transcriptNoticeResult(_notice()),
      'First useful result\n\nSecond useful result',
    );
    for (final separator in ['\n', '\r\n']) {
      final prefix =
          '[ASYNC DELEGATION COMPLETE — task]${separator}Private preamble$separator--- RESULT ---$separator';
      expect(
        transcriptNoticeResult({
          ..._notice(),
          'content': '${prefix}Useful report',
        }),
        'Useful report',
      );
      expect(
        transcriptNoticeResult({
          ..._notice(),
          'content':
              '${prefix}Cron job probe\nPrivate details\n--- JOB OUTPUT ---\nUseful report',
        }),
        'Useful report',
      );
    }
    expect(
      transcriptNoticeResult({
        ..._notice(),
        'content': '[ASYNC DELEGATION COMPLETE — task]\nPrivate preamble',
      }),
      isNull,
    );
    expect(
      transcriptNoticeResult({
        ..._notice(),
        'content': 'Already unwrapped report',
      }),
      'Already unwrapped report',
    );
    expect(
      transcriptNoticeResult({
        ..._notice(),
        'content': '',
        'display_content': 'Projected report',
      }),
      'Projected report',
    );
  });

  test(
    'technical discussion, quoted envelopes and assistant text stay visible',
    () {
      for (final text in [
        _envelope,
        'Why does this appear?\n$_envelope',
        '```text\n$_envelope\n```',
        '[ASYNC DELEGATION COMPLETE]',
        'The model_switch event is useful to debug.',
      ]) {
        final row = {'role': 'user', 'content': text};
        expect(transcriptNoticeKind(row), isNull);
        expect(isAnswerPrompt(row), isTrue);
        expect(groupTranscriptSections([row]).single.messages.single, row);
      }
      expect(
        transcriptNoticeKind({'role': 'assistant', 'content': _envelope}),
        isNull,
      );
    },
  );

  test('regeneration targets the human prompt before a typed notice', () {
    final target = AnswerTarget.at([
      {'role': 'user', 'content': 'Compare the options'},
      _notice(),
      {'role': 'assistant', 'content': 'Here is the comparison'},
    ], 2)!;
    expect(target.userOrdinal, 0);
    expect(target.prompt, 'Compare the options');
  });
}
