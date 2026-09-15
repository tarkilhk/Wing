import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/profile_transcript.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/profile_history_fixture.dart';

class _ToolHistoryFixture extends ProfileHistoryFixture {
  int toolCount = 36;
  bool includeConversation = true;
  bool includeLatestCommentary = false;

  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    ...super.historyRows(profile, id),
    if (includeConversation) ...[
      {'id': 621, 'role': 'user', 'content': 'Check the latest results'},
      {'id': 622, 'role': 'assistant', 'content': 'I am checking the results.'},
    ],
    for (var i = 0; i < toolCount; i++) ...[
      {'id': 623 + i * 2, 'role': 'assistant', 'content': ''},
      {
        'id': 624 + i * 2,
        'role': 'tool',
        'tool_name': 'browser_vision',
        'content': 'Tool result $i',
      },
    ],
    if (includeLatestCommentary)
      {'id': 2000, 'role': 'assistant', 'content': 'Checking one more source'},
  ];
}

void main() {
  late _ToolHistoryFixture host;
  late ProfileWorkspaceController controller;

  Future<void> initialize() async {
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Test',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'test',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = _ToolHistoryFixture();
    await initialize();
  });
  tearDown(() => controller.dispose());

  Future<ProfileChat> open() async {
    await controller.openSession(
      ProfileSessionKey(controller.current!.scope, 'chat-0'),
    );
    return controller.current!.chat!;
  }

  void expectLatestConversation(ProfileChat chat) {
    expect(
      chat.messages.any((row) => row['id'] == 621),
      isTrue,
      reason:
          'The latest user prompt must appear without loading older messages',
    );
    expect(
      chat.messages.any((row) => row['id'] == 622),
      isTrue,
      reason: 'The latest assistant text must survive a long run of tool calls',
    );
    expect(chat.messages.last['id'], 622 + host.toolCount * 2);
  }

  test('opening a tool-heavy chat includes its latest conversation', () async {
    final chat = await open();
    expectLatestConversation(chat);
    expect(chat.nextHistoryOffset, 100);
    await controller.loadOlderMessages(chat);
    expect(chat.messages.first['id'], 545);
    expect(chat.messages.map((row) => row['id']).toSet(), hasLength(150));
  });

  test('commentary among tool calls still loads their user prompt', () async {
    host.includeLatestCommentary = true;
    final chat = await open();
    expect(chat.messages.any((row) => row['id'] == 621), isTrue);
    expect(chat.messages.last['content'], 'Checking one more source');
  });

  test(
    'reopening after more tool calls keeps the latest conversation',
    () async {
      host.toolCount = 0;
      final chat = await open();
      controller.showList();
      host.toolCount = 90;
      await open();
      expectLatestConversation(chat);
      expect(chat.nextHistoryOffset, 200);
    },
  );

  test(
    'pending chat recovery hydrates the conversation before opening',
    () async {
      final key = ProfileSessionKey(controller.current!.scope, 'chat-0');
      await (await SharedPreferences.getInstance()).setStringList(
        'profile_pending_v2_test',
        [jsonEncode(key.toJson())],
      );
      controller.dispose();
      await initialize();
      final chat = controller.current!.chats['chat-0']!;
      expect(chat.title, 'personal chat 0');
      expectLatestConversation(chat);
    },
  );

  test('history without a user prompt stops at the beginning', () async {
    host.messageCount = 0;
    host.includeConversation = false;
    final chat = await open();
    expect(chat.messages, hasLength(72));
    expect(chat.nextHistoryOffset, isNull);
    expect(chat.historyError, isNull);
  });

  test('failed backfill preserves the latest page and can retry', () async {
    final delay = host.historyDelays[('chat-0', 50)] = Completer<void>();
    final pending = open();
    while (!host.reads.any(
      (read) => read.$2['offset'] == '50' && read.$1.endsWith('/messages'),
    )) {
      await Future<void>.delayed(Duration.zero);
    }
    host.failHistory = true;
    delay.complete();
    final chat = await pending;
    expect(chat.messages, hasLength(50));
    expect(chat.historyError, isNotNull);
    expect(chat.nextHistoryOffset, 50);
    host.failHistory = false;
    await controller.refreshHistory(chat);
    expectLatestConversation(chat);
    expect(chat.historyError, isNull);
  });

  test('navigation invalidates a delayed initial backfill', () async {
    final delay = host.historyDelays[('chat-0', 50)] = Completer<void>();
    final pending = controller.openSession(
      ProfileSessionKey(controller.current!.scope, 'chat-0'),
    );
    while (!host.reads.any(
      (read) => read.$2['offset'] == '50' && read.$1.endsWith('/messages'),
    )) {
      await Future<void>.delayed(Duration.zero);
    }
    final chat = controller.current!.chat!;
    controller.showList();
    delay.complete();
    await pending;
    expect(controller.current!.chat, isNull);
    expect(chat.messages, hasLength(50));
    expect(chat.historyLoading, isFalse);
  });

  testWidgets('latest conversation is visible above collapsed tool calls', (
    tester,
  ) async {
    final chat = await open();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileTranscript(
            chat: chat,
            controller: controller,
            messageBuilder: (message) => Text(message['content'] as String),
            tail: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Check the latest results').hitTestable(), findsOneWidget);
    expect(
      find.text('I am checking the results.').hitTestable(),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
