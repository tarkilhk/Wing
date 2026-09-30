import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  Future<ProfileWorkspaceController> initialize(Host host) async {
    SharedPreferences.setMockInitialValues({});
    final controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'streaming-presentation',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    return controller;
  }

  testWidgets('text ingestion is immediate and phase changes publish at once', (
    tester,
  ) async {
    final host = Host();
    final controller = await initialize(host);
    addTearDown(controller.dispose);
    final chat = await controller.createChat();
    host.event('a', 'message.start');
    await tester.pump();
    var updates = 0;
    controller.addListener(() => updates++);

    host.event('a', 'message.delta', {'text': 'First'});
    expect(updates, 1);
    host.event('a', 'message.delta', {'text': ' second'});
    expect(chat.streaming, 'First second');
    expect(updates, 1);
    await tester.pump(const Duration(milliseconds: 99));
    expect(updates, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(updates, 2);

    host.event('a', 'reasoning.delta', {'text': 'Thinking'});
    expect(chat.mainActivity, ProfileMainActivity.thinking);
    expect(updates, 3);
    host.event('a', 'reasoning.delta', {'text': ' more'});
    expect(chat.reasoning, 'Thinking more');
    expect(updates, 3);
    host.event('a', 'message.delta', {'text': ' third'});
    expect(chat.mainActivity, ProfileMainActivity.writing);
    expect(updates, 4);
    expect(chat.streaming, 'First second third');
    await tester.pump(const Duration(milliseconds: 100));
    expect(updates, 4);
  });

  for (final event in ['approval', 'turn.error', 'message.interim']) {
    testWidgets('$event publishes pending text without waiting for a timer', (
      tester,
    ) async {
      final host = Host();
      final controller = await initialize(host);
      addTearDown(controller.dispose);
      final chat = await controller.createChat();
      host.event('a', 'message.start');
      await tester.pump();
      var updates = 0;
      controller.addListener(() => updates++);
      host.event('a', 'message.delta', {'text': 'First'});
      host.event('a', 'message.delta', {'text': ' pending'});
      expect(updates, 1);

      host.event('a', event, {
        if (event == 'approval') ...{
          'request_id': 'review',
          'command': 'test command',
        },
        if (event == 'turn.error') 'message': 'Provider stopped',
      });
      expect(updates, 2);
      if (event == 'approval') {
        expect(chat.approval?['request_id'], 'review');
        expect(chat.status, ProfileTurnStatus.attention);
        expect(chat.streaming, 'First pending');
      } else if (event == 'turn.error') {
        expect(chat.error, 'Provider stopped');
        expect(chat.status, ProfileTurnStatus.failed);
        expect(chat.streaming, 'First pending');
      } else {
        expect(chat.messages.last['content'], 'First pending');
        expect(chat.streaming, isEmpty);
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(updates, 2);
    });
  }

  testWidgets('one chat error publishes other chats pending text and rows', (
    tester,
  ) async {
    final host = Host();
    final controller = await initialize(host);
    addTearDown(controller.dispose);
    final a = await controller.createChat();
    host.event('a', 'message.start');
    host.event('a', 'message.delta', {'text': 'A'});
    await controller.switchProfile('b');
    // Host's replacement counter is global; this is B's first independent chat.
    host.sessionCreates = 0;
    final b = await controller.createChat();
    host.event('b', 'message.start');
    await tester.pump();
    host.event('a', 'message.delta', {'text': ''});
    host.event('b', 'message.delta', {'text': 'B'});
    var updates = 0;
    controller.addListener(() => updates++);
    host.event('a', 'message.delta', {'text': ' pending'});
    host.event('b', 'message.delta', {'text': ' pending'});
    expect(updates, 0);
    host.event('a', 'turn.error', {'message': 'A stopped'});
    expect(updates, 1);
    expect(a.streaming, 'A pending');
    expect(b.streaming, 'B pending');
    expect(b.status, ProfileTurnStatus.running);
    expect(controller.browserChanges.value.chat, isNull);
    await tester.pump(const Duration(milliseconds: 100));
    expect(updates, 1);
  });

  testWidgets('disposing with pending text cancels trailing presentation', (
    tester,
  ) async {
    final host = Host();
    final controller = await initialize(host);
    final chat = await controller.createChat();
    host.event('a', 'message.start');
    var updates = 0;
    controller.addListener(() => updates++);
    host.event('a', 'message.delta', {'text': 'First'});
    host.event('a', 'message.delta', {'text': ' pending'});
    expect(chat.streaming, 'First pending');
    controller.dispose();
    await tester.pump(const Duration(milliseconds: 100));
    expect(updates, 1);
    expect(tester.takeException(), isNull);
  });
}
