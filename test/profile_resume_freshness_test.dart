import 'package:wing/core/models/chat_runtime.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  late Host host;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = Host()..running = false;
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'resume-freshness',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat(canDispatch: () => true);
  });
  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });

  Future<void> resume(String path) async {
    switch (path) {
      case 'open':
        await controller.openSession(chat.key);
      case 'reconnect':
        await controller.reconnect(chat.key.workspace);
      case 'queue':
        await controller.resumeQueue(chat);
    }
  }

  test('only the latest started resume may publish a snapshot', () async {
    final olderDelay = Completer<void>();
    host
      ..running = true
      ..resumeStarted = Completer<void>()
      ..resumeDelay = olderDelay;
    final older = controller.openSession(chat.key);
    await host.resumeStarted!.future;
    final newerDelay = Completer<void>();
    host
      ..running = false
      ..resumeStarted = Completer<void>()
      ..resumeDelay = newerDelay;
    final newer = controller.openSession(chat.key);
    await host.resumeStarted!.future;
    olderDelay.complete();
    await older;
    expect(chat.runtime.execution, ChatExecution.idle);
    newerDelay.complete();
    await newer;
    expect(chat.runtime.execution, ChatExecution.idle);
  });

  test('a delayed resume cannot rebind an already replaced runtime', () async {
    final delay = Completer<void>();
    host
      ..resumeStarted = Completer<void>()
      ..resumeDelay = delay;
    final opening = controller.openSession(chat.key);
    await host.resumeStarted!.future;
    host.runtimeForResume['a'] = 'newer-runtime';
    await controller.openSession(chat.key);
    delay.complete();
    expect(await opening, isNull);
    expect(chat.runtime.runtimeId, 'newer-runtime');
  });

  test('usage observations do not prevent execution recovery', () async {
    host.event('a', 'message.start');
    controller
        .browserResource(chat.key.workspace.profileName)
        .gateway
        .onConnectionChanged!(false);
    final delay = Completer<void>();
    host
      ..running = false
      ..resumeStarted = Completer<void>()
      ..resumeDelay = delay;
    final recovering = controller.reconnect(chat.key.workspace);
    await host.resumeStarted!.future;
    host.event('a', 'session.usage', {
      'usage': {'input_tokens': 42},
    });
    delay.complete();
    await recovering;

    expect(chat.runtime.blocksTurnAdmission, isFalse);
    expect(chat.runtime.execution, ChatExecution.completed);
    expect(controller.current!.recovering, isFalse);
    expect(controller.current!.reconnectScheduled, isFalse);
  });

  test('superseded history failure cannot fail a recovered profile', () async {
    final delay = Completer<void>();
    addTearDown(() {
      if (!delay.isCompleted) delay.complete();
    });
    host
      ..heldHistoryStarted = Completer<void>()
      ..heldHistoryDelay = delay
      ..heldHistoryFailure = const FormatException('Invalid older history');
    final recovering = controller.reconnect(chat.key.workspace);
    await host.heldHistoryStarted!.future;

    host.event('a', 'message.start');
    host.event('a', 'message.complete', {'text': 'Newer completed answer'});
    await controller.refreshHistory(chat);
    expect(chat.runtime.blocksTurnAdmission, isFalse);
    expect(chat.reading.historyError, isNull);
    delay.complete();
    await recovering;

    expect(chat.runtime.execution, ChatExecution.completed);
    expect(chat.reading.historyError, isNull);
    expect(controller.current!.reconnectError, isNull);
    expect(controller.current!.recovering, isFalse);
    expect(controller.connectionStatus.recoveryProblem, isNull);
    expect(controller.current!.reconnectScheduled, isFalse);
    expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
  });

  test('current history failure still fails profile recovery', () async {
    final delay = Completer<void>();
    addTearDown(() {
      if (!delay.isCompleted) delay.complete();
    });
    host
      ..heldHistoryStarted = Completer<void>()
      ..heldHistoryDelay = delay
      ..heldHistoryFailure = const FormatException('Invalid current history');
    final recovering = controller.reconnect(chat.key.workspace);
    await host.heldHistoryStarted!.future;
    delay.complete();
    await recovering;

    expect(chat.reading.historyError, isNotNull);
    expect(controller.current!.reconnectError, isNotNull);
    expect(controller.connectionStatus.recoveryProblem, isNotNull);
    expect(controller.current!.reconnectScheduled, isFalse);
  });

  for (final path in ['open', 'reconnect', 'queue']) {
    test(
      '$path: older idle resume cannot erase newer live text or input',
      () async {
        final delay = Completer<void>();
        host
          ..resumeStarted = Completer<void>()
          ..resumeDelay = delay;
        final opening = resume(path);
        await host.resumeStarted!.future;
        host.event('a', 'message.start');
        host.event('a', 'message.delta', {'text': 'New live answer'});
        host.event('a', 'clarify', {
          'request_id': 'new-question',
          'question': 'Which destination?',
          'choices': ['Home', 'Work'],
        });
        delay.complete();
        await opening;

        expect(chat.reading.streaming, 'New live answer');
        expect(chat.runtime.needsInput, isTrue);
        expect(
          chat.runtime.questions?.questions.first.requestId,
          'new-question',
        );
      },
    );

    test(
      '$path: older running resume cannot resurrect a completed turn',
      () async {
        host.running = true;
        host.event('a', 'message.start');
        final delay = Completer<void>();
        host
          ..resumeStarted = Completer<void>()
          ..resumeDelay = delay;
        final opening = resume(path);
        await host.resumeStarted!.future;
        host.event('a', 'message.complete', {'text': 'Final answer'});
        delay.complete();
        await opening;

        expect(chat.runtime.blocksTurnAdmission, isFalse);
        expect(chat.reading.streaming, isEmpty);
      },
    );
  }
}
