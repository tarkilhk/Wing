import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/answer_versions.dart';
import 'package:hermes_android/core/models/transcript_notice.dart';
import 'package:hermes_android/core/models/skill_invocation.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/widgets/profile_message.dart';
import 'package:hermes_android/core/widgets/chat_find_sheet.dart';
import 'package:hermes_android/core/services/profile_gateway.dart';
import 'package:hermes_android/core/widgets/profile_tool_activity.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_history_fixture.dart';
import 'support/process_batch_fixture.dart';
import 'task_snapshot_visibility_test.dart' show snapshot, snapshotHeader;

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

const _processEnvelope =
    '[IMPORTANT: Background process proc_0c3ef9a5dfb0 completed normally (exit code 0).\nCommand: env -u ANTHROPIC_API_KEY claude --print\nOutput:\n]';
const _agentEnvelope =
    'Message from 🤖 Hermes (@hermes): Private agent instructions';
const _skillEnvelope =
    '[IMPORTANT: The user has invoked the "work" skill, indicating they want you to follow its instructions.\nThe full skill content is loaded below.]\nPrivate skill body\nThe user has provided the following instruction alongside the skill invocation: fix the leak\n\n[Runtime note: private]';
const _continuationHeader =
    '[STILL IN PROGRESS — this is the active request, restated after the '
    'compaction boundary because it was not finished yet. Continue it; '
    'do not start over.]';
const _continuationEnvelope =
    '$_continuationHeader\nPlease diagnose the browser/vault failure on this VM.';

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
    {'id': 5, 'role': 'user', 'content': _processEnvelope},
    {'id': 6, 'role': 'user', 'content': _agentEnvelope},
    {'id': 7, 'role': 'assistant', 'content': 'Private agent reply'},
    {'id': 8, 'role': 'user', 'content': _skillEnvelope},
    {'id': 9, 'role': 'user', 'content': processBatchEnvelope},
    {'id': 10, 'role': 'user', 'content': snapshot},
    {'id': 11, 'role': 'user', 'content': _continuationEnvelope},
  ];
}

void main() {
  test('continuation reminders are hidden across message encodings', () {
    for (final fields in <Map<String, dynamic>>[
      {'content': _continuationEnvelope},
      {'text': _continuationEnvelope},
      {'content': _continuationEnvelope.replaceAll('\n', '\r\n')},
      {'content': '  $_continuationEnvelope\n'},
      {'content': 'wire payload', 'display_content': _continuationEnvelope},
      {
        'content': [
          {'type': 'text', 'text': _continuationEnvelope},
        ],
      },
    ]) {
      final row = {'role': 'user', ...fields};
      expect(isHiddenAnswerMessage(row), isTrue, reason: '$fields');
      expect(isHumanAnswerPrompt(row), isFalse);
      expect(isHiddenAnswerMessage(answerHistoryRows([row]).single), isTrue);
      // Filtering must not change the stored history's rewind ordinals.
      expect(isAnswerPrompt(row), isTrue);
    }
  });

  test('quoted and ordinary progress messages remain visible', () {
    for (final text in [
      'Explain this:\n$_continuationEnvelope',
      '```\n$_continuationEnvelope\n```',
      '> $_continuationEnvelope',
      '[STILL IN PROGRESS] Please continue my request.',
      '[STILL IN PROGRESS — this is the active request',
      _continuationHeader,
    ]) {
      final row = {'role': 'user', 'content': text};
      expect(isHiddenAnswerMessage(row), isFalse, reason: text);
      expect(isHumanAnswerPrompt(row), isTrue);
      expect(answerMessageDisplayText(row), text);
    }
    expect(
      isHiddenAnswerMessage({
        'role': 'assistant',
        'content': _continuationEnvelope,
      }),
      isFalse,
    );
    expect(
      isHiddenAnswerMessage({
        'role': 'user',
        'content': _continuationEnvelope,
        'display_content': 'Server-projected user text',
      }),
      isFalse,
    );
  });

  testWidgets('continuation reminder never renders a chat bubble', (
    tester,
  ) async {
    const row = {'role': 'user', 'content': _continuationEnvelope};
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProfileMessage(message: row)),
      ),
    );
    expect(find.textContaining(_continuationHeader), findsNothing);
    expect(find.byTooltip('Copy message'), findsNothing);
    expect(answerMessageText(row), _continuationEnvelope);
    final sections = groupTranscriptSections([
      {'id': 1, 'role': 'tool', 'content': 'first'},
      row,
      {'id': 2, 'role': 'tool', 'content': 'second'},
    ]);
    expect(sections, hasLength(1));
    expect(sections.single.messages.map((row) => row['id']), [1, 2]);
  });

  for (final width in [360.0, 900.0]) {
    testWidgets('producer batch renders one compact notice at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileMessage(
                message: {'role': 'user', 'content': processBatchEnvelope},
              ),
            ),
          ),
        ),
      );
      expect(find.text(processBatchEnvelope), findsNothing);
      expect(find.byTooltip('Copy message'), findsNothing);
      expect(find.text('16 background processes completed'), findsOneWidget);
      expect(find.textContaining('Action needed'), findsNothing);
      await tester.tap(find.text('Output'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Action needed: check failed'),
        findsOneWidget,
      );
      expect(find.textContaining('[IMPORTANT:'), findsNothing);
      expect(find.textContaining('Treat these results'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('process completion never exposes its delivery envelope', (
    tester,
  ) async {
    const envelope =
        '[IMPORTANT: Background process proc_0c3ef9a5dfb0 '
        'completed normally (exit code 0).\n'
        'Command: env -u ANTHROPIC_API_KEY claude --print\nOutput:\n]';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileMessage(message: {'role': 'user', 'content': envelope}),
        ),
      ),
    );
    expect(find.text(envelope), findsNothing);
    expect(find.byTooltip('Copy message'), findsNothing);
  });
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
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
        expect(find.byKey(const ValueKey('edit-message-5')), findsNothing);
        expect(find.byKey(const ValueKey('edit-message-6')), findsNothing);
        expect(find.byKey(const ValueKey('answer-actions-7')), findsNothing);
        expect(find.text('Private agent reply'), findsNothing);
        expect(find.text('Replied to Hermes'), findsOneWidget);
        expect(find.text(_processEnvelope), findsNothing);
        expect(find.text(_agentEnvelope), findsNothing);
        expect(find.text(_skillEnvelope), findsNothing);
        expect(find.text('/work fix the leak'), findsOneWidget);
        expect(find.text(processBatchEnvelope), findsNothing);
        expect(find.text('16 background processes completed'), findsOneWidget);
        expect(find.byKey(const ValueKey('edit-message-9')), findsNothing);
        expect(find.textContaining(snapshotHeader), findsNothing);
        expect(find.byKey(const ValueKey('edit-message-10')), findsNothing);
        expect(find.textContaining(_continuationHeader), findsNothing);
        expect(find.byKey(const ValueKey('edit-message-11')), findsNothing);
        // Retain server history and IDs for paging/rewind; filter only the view.
        expect(chat.messages.map((row) => row['id']), [
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          10,
          11,
        ]);
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
    await tester.enterText(find.byType(TextField), 'Private hidden');
    await tester.pump();
    expect(find.textContaining('Private instructions'), findsNothing);
    expect(find.text('Private hidden instructions'), findsNothing);
    expect(find.text('View in chat'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Quiesce processing');
    await tester.pump();
    expect(find.textContaining(snapshotHeader), findsNothing);
    expect(find.text('View in chat'), findsNothing);
    await tester.enterText(find.byType(TextField), 'browser/vault failure');
    await tester.pump();
    expect(find.textContaining(_continuationHeader), findsNothing);
    expect(find.text('View in chat'), findsNothing);
    await tester.enterText(find.byType(TextField), 'First useful result');
    await tester.pump();
    expect(find.textContaining('First useful result'), findsWidgets);
    expect(find.text('1 matching message'), findsOneWidget);
    expect(find.text('system'), findsOneWidget);
  });

  for (final width in [360.0, 900.0]) {
    for (final envelope in [
      _processEnvelope,
      _agentEnvelope,
      "[Message from agent 'legacy'] Delivered text",
    ]) {
      testWidgets('delivery at $width: ${envelope.substring(0, 30)}', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final row = {'role': 'user', 'content': envelope};
        final delivery = transcriptUserDelivery(row)!;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ProfileMessage(message: row)),
          ),
        );
        expect(find.text(envelope), findsNothing);
        expect(find.text(delivery.headline), findsOneWidget);
        expect(find.text(delivery.detail), findsNothing);
        expect(find.byTooltip('Copy message'), findsNothing);
        expect(isHumanAnswerPrompt(row), isFalse);
        await tester.tap(find.text(delivery.disclosure));
        await tester.pumpAndSettle();
        expect(find.text(delivery.detail), findsOneWidget);
        expect(find.text(envelope), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('Desktop envelope matching preserves ordinary technical discussion', () {
    for (final text in [
      'Why did this happen?\n$_processEnvelope',
      '```\n$_processEnvelope\n```',
      '[IMPORTANT: Background process unfinished',
      '[IMPORTANT: read the docs]',
      'I got a Message from 🤖 Hermes: earlier',
      'can you explain what Message from means?',
    ]) {
      final row = {'role': 'user', 'content': text};
      expect(transcriptNoticeKind(row), isNull);
      expect(isHumanAnswerPrompt(row), isTrue);
      expect(answerMessageDisplayText(row), text);
    }
    for (final text in [_processEnvelope, _agentEnvelope]) {
      expect(
        transcriptNoticeKind({'role': 'assistant', 'content': text}),
        isNull,
      );
    }
    expect(
      transcriptNoticeResult({
        'role': 'user',
        'text': _processEnvelope.replaceAll('\n', '\r\n'),
      }),
      'Command: env -u ANTHROPIC_API_KEY claude --print\r\nOutput:',
    );
    expect(
      transcriptUserDelivery({
        'role': 'user',
        'content': 'wire payload',
        'display_content': _agentEnvelope,
      })?.headline,
      'Message from Hermes',
    );
    expect(
      transcriptNoticeResult({
        'role': 'user',
        'content': '[IMPORTANT: Background process 1 finished]',
      }),
      isNull,
    );
    for (final text in [
      'Message from Turquoise: ready',
      'Message from 🤖 Dev: line one\nline two',
      "[Message from agent 'legacy'] ping",
    ]) {
      expect(
        transcriptNoticeKind({'role': 'user', 'content': text}),
        'agent_message',
      );
    }
  });

  test('skill scaffold matches Desktop single and bundle projection', () {
    expect(skillInvocationText(_skillEnvelope), '/work fix the leak');
    expect(
      skillInvocationText(
        _skillEnvelope.replaceFirst('fix the leak', 'fix\n\nthe leak'),
      ),
      '/work fix the leak',
    );
    expect(
      skillInvocationText(
        '[IMPORTANT: The user has invoked the "work" skill.\nThe full skill content is loaded below.]\nPrivate body',
      ),
      '/work',
    );
    expect(
      skillInvocationText(
        '[IMPORTANT: The user has invoked the "/clean /work" stacked skill bundle, loading 2 skills together.]\n\nUser instruction: ship it\n\n[Loaded as part of the stacked skill invocation "clean".]\nPrivate body',
      ),
      '/clean /work ship it',
    );
    expect(skillInvocationText('[IMPORTANT: read the docs]'), isNull);
    expect(
      answerMessageDisplayText({
        'role': 'assistant',
        'content': _skillEnvelope,
      }),
      _skillEnvelope,
    );
  });

  test('agent reply classification stops at the next human or assistant', () {
    final messages = <Map<String, dynamic>>[
      {'role': 'user', 'content': _agentEnvelope},
      {'role': 'system', 'content': 'status'},
      {'role': 'assistant', 'content': 'Reply'},
      {'role': 'assistant', 'content': 'Another answer'},
      {'role': 'user', 'content': 'Human prompt'},
      {'role': 'assistant', 'content': 'Human answer'},
    ];
    expect(interAgentReplySender(messages, 2), 'Hermes');
    expect(interAgentReplySender(messages, 3), isNull);
    expect(interAgentReplySender(messages, 5), isNull);
    // Untyped deliveries retain their durable ordinal for existing history APIs.
    expect(AnswerTarget.at(messages, 5)!.userOrdinal, 1);
  });

  testWidgets('system status is compact and strips the slash protocol marker', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileMessage(
            message: {
              'role': 'system',
              'content': 'slash:/model\nModel changed',
            },
          ),
        ),
      ),
    );
    expect(find.text('/model · Model changed'), findsOneWidget);
    expect(find.text('System'), findsNothing);
    expect(find.byTooltip('Copy message'), findsNothing);
  });

  testWidgets('search projects deliveries and skills without their wrappers', (
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
    for (final query in [
      'IMPORTANT',
      'Private skill body',
      'Runtime note',
      '(@hermes)',
      'Treat these results as one batch',
    ]) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump();
      expect(find.text('View in chat'), findsNothing);
    }
    await tester.enterText(
      find.byType(TextField),
      'Private agent instructions',
    );
    await tester.pump();
    expect(find.text('1 matching message'), findsOneWidget);
    expect(find.text('system'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      'Action needed: check failed',
    );
    await tester.pump();
    expect(find.text('1 matching message'), findsOneWidget);
    expect(find.textContaining('Treat these results'), findsNothing);
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
