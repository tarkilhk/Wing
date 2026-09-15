import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_transcript.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'support/profile_history_fixture.dart';

void main() {
  late ProfileWorkspaceController controller;
  late ProfileHistoryFixture host;
  late List<(String, Map<String, dynamic>)> runtimeReads;
  late List<(String, Map<String, String>)> durableReads;
  int? httpError;
  Object? rpcError;
  Map<String, dynamic> runtimeResult = {};
  Completer<void>? runtimeDelay;
  bool malformedPage = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = ProfileHistoryFixture()..messageCount = 0;
    runtimeReads = [];
    durableReads = [];
    httpError = 404;
    rpcError = null;
    runtimeResult = {'count': 0, 'messages': []};
    runtimeDelay = null;
    malformedPage = false;
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Test',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'empty-history-test',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: (scope) {
        final delegate = host.gateway(scope);
        return ProfileGateway(
          scope: scope,
          discover: delegate.discover,
          get: (endpoint, query) async {
            if (endpoint.endsWith('/messages')) {
              durableReads.add((endpoint, query));
              if (httpError != null) {
                throw DashboardHttpException(httpError!, endpoint);
              }
              if (malformedPage) return {'messages': []};
            }
            return delegate.read(endpoint, query);
          },
          rpc: (method, params) async {
            if (method == 'session.history') {
              runtimeReads.add((method, params));
              final result = runtimeResult;
              await runtimeDelay?.future;
              if (rpcError != null) throw rpcError!;
              return result;
            }
            return delegate.call(method, params);
          },
        );
      },
    );
    await controller.initialize();
  });
  tearDown(() => controller.dispose());

  test(
    'new chat loads empty runtime history before durable persistence',
    () async {
      final chat = await controller.createChat();
      expect(chat.historyError, isNull);
      expect(chat.messages, isEmpty);
      expect(chat.historyLoading, isFalse);
      expect(chat.nextHistoryOffset, isNull);
      expect(durableReads.single.$1, 'sessions/new-chat/messages');
      expect(durableReads.single.$2['profile'], 'personal');
      expect(runtimeReads.single.$2, {
        'session_id': 'runtime',
        'profile': 'personal',
      });
    },
  );

  test('successful empty database history needs no runtime request', () async {
    httpError = null;
    final chat = await controller.createChat();
    expect(chat.historyError, isNull);
    expect(chat.messages, isEmpty);
    expect(chat.nextHistoryOffset, isNull);
    expect(durableReads, hasLength(1));
    expect(runtimeReads, isEmpty);
  });

  test(
    'live history retains messages and does not invent a next page',
    () async {
      runtimeResult = {
        'messages': List.generate(
          ProfileGateway.historyPageSize,
          (i) => {'role': 'assistant', 'content': 'Live message $i'},
        ),
      };
      final chat = await controller.createChat();
      expect(chat.historyError, isNull);
      expect(chat.messages, hasLength(ProfileGateway.historyPageSize));
      expect(chat.messages.last['content'], 'Live message 49');
      expect(chat.nextHistoryOffset, isNull);
    },
  );

  test('refresh uses database pagination once the chat is persisted', () async {
    final chat = await controller.createChat();
    httpError = null;
    host.messageCount = 60;
    await controller.refreshHistory(chat);
    expect(chat.messages.first['id'], 11);
    expect(chat.messages.last['id'], 60);
    expect(chat.nextHistoryOffset, 50);
    await controller.loadOlderMessages(chat);
    expect(chat.messages, hasLength(60));
    expect(chat.nextHistoryOffset, isNull);
    expect(runtimeReads, hasLength(1));
  });

  for (final status in [401, 403, 500]) {
    test('HTTP $status remains a history error', () async {
      httpError = status;
      final chat = await controller.createChat();
      expect(chat.historyError, isNotNull);
      expect(chat.historyLoading, isFalse);
      expect(runtimeReads, isEmpty);
    });
  }

  test('malformed empty database response remains an error', () async {
    httpError = null;
    malformedPage = true;
    final chat = await controller.createChat();
    expect(chat.historyError, isNotNull);
    expect(runtimeReads, isEmpty);
  });

  test('missing runtime history is not treated as an empty success', () async {
    runtimeResult = {};
    final chat = await controller.createChat();
    expect(chat.historyError, isNotNull);
  });

  test('404 without a live runtime remains an error', () async {
    final chat = await controller.createChat();
    chat.runtimeId = '';
    await controller.refreshHistory(chat);
    expect(chat.historyError, isNotNull);
    expect(runtimeReads, hasLength(1));
  });

  test(
    'missing older page does not replace saved history with live history',
    () async {
      httpError = null;
      host.messageCount = 60;
      final chat = await controller.createChat();
      httpError = 404;
      await controller.loadOlderMessages(chat);
      expect(chat.historyError, isNotNull);
      expect(chat.messages, hasLength(50));
      expect(chat.nextHistoryOffset, 50);
      expect(runtimeReads, isEmpty);
    },
  );

  test(
    'late live response cannot overwrite a newer persisted refresh',
    () async {
      final chat = await controller.createChat();
      runtimeDelay = Completer<void>();
      final pending = controller.refreshHistory(chat);
      await Future<void>.delayed(Duration.zero);
      httpError = null;
      host.messageCount = 2;
      await controller.refreshHistory(chat);
      runtimeDelay!.complete();
      await pending;
      expect(chat.messages, hasLength(2));
      expect(chat.messages.last['id'], 2);
      expect(chat.historyError, isNull);
    },
  );

  testWidgets(
    'failed live history retries to an empty transcript without the error banner',
    (tester) async {
      rpcError = StateError('Runtime unavailable');
      final chat = await controller.createChat();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => ProfileTranscript(
                chat: chat,
                controller: controller,
                messageBuilder: (message) => Text(message['content'] as String),
                tail: const [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('History could not be loaded. Retry to reload.'),
        findsOneWidget,
      );
      expect(find.text('Refresh history'), findsOneWidget);
      rpcError = null;
      await tester.tap(find.text('Refresh history'));
      await tester.pumpAndSettle();
      expect(chat.historyError, isNull);
      expect(chat.messages, isEmpty);
      expect(
        find.text('History could not be loaded. Retry to reload.'),
        findsNothing,
      );
      expect(find.text('Refresh history'), findsNothing);
      expect(runtimeReads, hasLength(2));
    },
  );
}
