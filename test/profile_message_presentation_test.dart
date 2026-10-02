import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/ws_client.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_history_fixture.dart';

class _PresentationHost extends ProfileHistoryFixture {
  List<Map<String, dynamic>> rows = [
    {'id': 1, 'role': 'user', 'content': 'Original prompt'},
  ];

  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => rows;
}

Future<void> _historyFinished(ProfileChat chat) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (chat.historyLoading && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(chat.historyLoading, isFalse, reason: 'History must finish promptly');
}

void main() {
  late _PresentationHost host;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = _PresentationHost();
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'message-presentation',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    chat = ProfileChat(
      key: ProfileSessionKey(controller.current!.scope, 'chat-0'),
      runtimeId: 'runtime',
      title: 'Presentation test',
    );
    controller.current!.chats['chat-0'] = chat;
    controller.current!.selectedSession = 'chat-0';
  });

  void emit(String type, Map<String, dynamic> data) {
    controller.current!.gateway.onEvent!(
      StreamEvent(type: type, sessionId: chat.runtimeId, data: data),
    );
  }

  Completer<void> pauseHistory() {
    final gate = Completer<void>();
    host.historyDelays[('chat-0', 0)] = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    return gate;
  }

  Map<String, dynamic> receipt(int id, {bool complete = true}) => {
    'row_ids': [id],
    'complete': complete,
    'final_assistant_row_id': id,
  };

  test(
    'interim seals its live segment and the next segment gets a new token',
    () {
      chat.status = ProfileTurnStatus.running;
      chat.streaming = 'Tool commentary';
      final first = chat.streamingMessage!;
      final firstToken = chat.messagePresentationId(first);

      emit('message.interim', {
        'text': 'Tool commentary',
        'already_streamed': true,
      });

      expect(chat.messages.single, same(first));
      expect(
        chat.messagePresentationId(chat.messages.single),
        same(firstToken),
      );
      expect(chat.streamingMessage, isNull);
      expect(chat.messages.single['id'], isNull);
      emit('message.delta', {'text': 'Final answer'});
      expect(chat.streamingMessage, isNot(same(first)));
      expect(
        chat.messagePresentationId(chat.streamingMessage!),
        isNot(same(firstToken)),
      );
    },
  );

  for (final complete in [true, false]) {
    test('final receipt retains identity with complete=$complete', () async {
      await controller.refreshHistory(chat);
      chat.status = ProfileTurnStatus.running;
      chat.streaming = 'Streamed prefix';
      final live = chat.streamingMessage!;
      final token = chat.messagePresentationId(live);
      host.rows = [
        host.rows.first,
        {'id': 2, 'role': 'assistant', 'content': 'Authoritative replacement'},
      ];
      final gate = pauseHistory();

      emit('message.complete', {
        'status': 'complete',
        'text': 'Authoritative replacement',
        'response_transformed': true,
        'persisted_turn': receipt(2, complete: complete),
      });

      expect(chat.messages.last, same(live));
      expect(chat.messages.last['content'], 'Authoritative replacement');
      expect(chat.messagePresentationId(chat.messages.last), same(token));
      expect(chat.streamingMessage, isNull);
      gate.complete();
      await _historyFinished(chat);
      expect(chat.historyError, isNull);
      expect(chat.messages.last['id'], 2);
      expect(chat.messagePresentationId(chat.messages.last), same(token));
    });
  }

  test('first saved history preserves a fresh chat receipt identity', () async {
    expect(chat.historySessionId, isNull);
    chat.status = ProfileTurnStatus.running;
    chat.streaming = 'New answer';
    final token = chat.messagePresentationId(chat.streamingMessage!);
    host.rows = [
      {'id': 2, 'role': 'assistant', 'content': 'New answer'},
    ];
    emit('message.complete', {
      'status': 'complete',
      'text': 'New answer',
      'persisted_turn': receipt(2, complete: false),
    });
    await _historyFinished(chat);
    expect(chat.historyError, isNull);
    expect(chat.historySessionId, 'chat-0');
    expect(chat.messages.single['id'], 2);
    expect(chat.messagePresentationId(chat.messages.single), same(token));
  });

  test(
    'receipt binds its row without stealing an equal older answer',
    () async {
      host.rows = [
        {'id': 1, 'role': 'assistant', 'content': 'Repeated answer'},
        {'id': 2, 'role': 'user', 'content': 'Ask again'},
      ];
      await controller.refreshHistory(chat);
      final oldToken = chat.messagePresentationId(chat.messages.first);
      chat.status = ProfileTurnStatus.running;
      chat.streaming = 'Repeated answer';
      final newToken = chat.messagePresentationId(chat.streamingMessage!);
      host.rows = [
        ...host.rows,
        {'id': 3, 'role': 'assistant', 'content': 'Repeated answer'},
      ];
      emit('message.complete', {
        'status': 'complete',
        'text': 'Repeated answer',
        'persisted_turn': receipt(3),
      });
      await _historyFinished(chat);
      expect(chat.messagePresentationId(chat.messages.first), same(oldToken));
      expect(chat.messagePresentationId(chat.messages.last), same(newToken));
      expect(newToken, isNot(same(oldToken)));
    },
  );

  test(
    'a final ID absent from receipt row IDs cannot prove presentation ownership',
    () async {
      chat.status = ProfileTurnStatus.running;
      chat.streaming = 'Unproven receipt';
      final token = chat.messagePresentationId(chat.streamingMessage!);
      host.rows = [
        {'id': 2, 'role': 'assistant', 'content': 'Unproven receipt'},
      ];
      emit('message.complete', {
        'status': 'complete',
        'text': 'Unproven receipt',
        'persisted_turn': {
          'row_ids': [3],
          'complete': false,
          'final_assistant_row_id': 2,
        },
      });
      await _historyFinished(chat);
      expect(chat.historyError, isNull);
      expect(chat.messages.single['id'], 2);
      expect(
        chat.messagePresentationId(chat.messages.single),
        isNot(same(token)),
      );
    },
  );

  test('previewed completion keeps the already sealed final segment', () async {
    emit('message.start', {});
    emit('message.delta', {'text': 'Previewed final'});
    final live = chat.streamingMessage!;
    final token = chat.messagePresentationId(live);
    emit('message.interim', {
      'text': 'Previewed final',
      'already_streamed': true,
    });
    expect(chat.messages.single, same(live));
    host.rows = [
      {'id': 2, 'role': 'assistant', 'content': 'Previewed final'},
    ];
    final gate = pauseHistory();
    emit('message.complete', {
      'status': 'complete',
      'text': 'Previewed final',
      'response_previewed': true,
      'persisted_turn': receipt(2),
    });
    expect(chat.messages, hasLength(1));
    expect(chat.messages.single, same(live));
    expect(chat.messagePresentationId(chat.messages.single), same(token));
    gate.complete();
    await _historyFinished(chat);
    expect(chat.messages, hasLength(1));
    expect(chat.messages.single['id'], 2);
    expect(chat.messagePresentationId(chat.messages.single), same(token));
  });

  test(
    'preview flag cannot claim an equal interim from a previous turn',
    () async {
      emit('message.start', {});
      emit('message.delta', {'text': 'Repeated final'});
      emit('message.interim', {
        'text': 'Repeated final',
        'already_streamed': true,
      });
      final previous = chat.messages.single;
      final oldToken = chat.messagePresentationId(previous);
      chat.status = ProfileTurnStatus.completed;
      emit('message.start', {});
      final gate = pauseHistory();
      emit('message.complete', {
        'status': 'complete',
        'text': 'Repeated final',
        'response_previewed': true,
      });
      expect(chat.messages, hasLength(2));
      expect(chat.messages.first, same(previous));
      expect(
        chat.messagePresentationId(chat.messages.last),
        isNot(same(oldToken)),
      );
      gate.complete();
      await _historyFinished(chat);
    },
  );

  test(
    'an omitted receipt row retains its proof for a later history page',
    () async {
      await controller.refreshHistory(chat);
      chat.status = ProfileTurnStatus.running;
      chat.streaming = 'Saved answer';
      final token = chat.messagePresentationId(chat.streamingMessage!);
      // The first successful history response does not yet include the row.
      emit('message.complete', {
        'status': 'complete',
        'text': 'Saved answer',
        'persisted_turn': receipt(2),
      });
      await _historyFinished(chat);
      expect(chat.historyError, isNull);
      expect(chat.messages.every((row) => row['id'] != 2), isTrue);
      host.rows = [
        ...host.rows,
        {'id': 2, 'role': 'assistant', 'content': 'Saved answer'},
      ];
      await controller.refreshHistory(chat);
      expect(chat.messagePresentationId(chat.messages.last), same(token));
    },
  );

  for (final status in ['interrupted', 'error']) {
    test(
      '$status retains the local partial segment without a fake row ID',
      () async {
        chat.status = ProfileTurnStatus.running;
        chat.streaming = 'Partial answer';
        final live = chat.streamingMessage!;
        final token = chat.messagePresentationId(live);
        host.failHistory = true;
        emit('message.complete', {'status': status, 'text': 'Partial answer'});
        await _historyFinished(chat);
        expect(chat.messages.single, same(live));
        expect(chat.messagePresentationId(chat.messages.single), same(token));
        expect(chat.messages.single['id'], isNull);
        expect(chat.streamingMessage, isNull);
        expect(
          chat.status,
          status == 'error'
              ? ProfileTurnStatus.failed
              : ProfileTurnStatus.cancelled,
        );
        expect(chat.historyError, isNotNull);
      },
    );
  }

  test(
    'optional missing receipt keeps local identity but does not invent proof',
    () async {
      chat.status = ProfileTurnStatus.running;
      chat.streaming = 'Unreceipted answer';
      final live = chat.streamingMessage!;
      final token = chat.messagePresentationId(live);
      host.rows = [
        {'id': 2, 'role': 'assistant', 'content': 'Unreceipted answer'},
      ];
      final gate = pauseHistory();
      emit('message.complete', {
        'status': 'complete',
        'text': 'Unreceipted answer',
      });
      expect(chat.messages.single, same(live));
      expect(chat.messagePresentationId(chat.messages.single), same(token));
      gate.complete();
      await _historyFinished(chat);
      expect(chat.historyError, isNull);
      expect(chat.messages.single['id'], 2);
      // No preceding durable boundary or receipt proves this row's identity.
      expect(
        chat.messagePresentationId(chat.messages.single),
        isNot(same(token)),
      );
    },
  );

  test(
    'an unproven segment does not bind equal text across history rotation',
    () async {
      await controller.refreshHistory(chat);
      chat.status = ProfileTurnStatus.running;
      chat.streaming = 'Same body';
      final token = chat.messagePresentationId(chat.streamingMessage!);
      host.historySessionIdOverride = 'rotated-chat';
      host.rows = [
        {'id': 10, 'role': 'user', 'content': 'Different turn'},
        {'id': 11, 'role': 'assistant', 'content': 'Same body'},
      ];
      emit('message.complete', {'status': 'complete', 'text': 'Same body'});
      await _historyFinished(chat);
      expect(chat.historyError, isNull);
      expect(chat.historySessionId, 'rotated-chat');
      expect(chat.messages.last['id'], 11);
      expect(
        chat.messagePresentationId(chat.messages.last),
        isNot(same(token)),
      );
    },
  );
}
