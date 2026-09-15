import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/profile_live_activity.dart';
import 'package:hermes_android/core/screens/workspace_overview_content.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/widgets/profile_chat_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;
import 'profile_live_activity_test.dart' show ActivityHost;

void main() {
  late Host host;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = Host()..running = false;
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'ongoing-activity',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
    chat.title = 'Delegated research';
  });

  tearDown(() => controller.dispose());

  void startChild() => host.event('a', 'subagent.start', {
    'subagent_id': 'child',
    'goal': 'Research',
  });

  testWidgets('idle parent with active child appears in Activities', (
    tester,
  ) async {
    startChild();
    expect(chat.status, ProfileTurnStatus.idle);
    expect(chat.subagents.single.isTerminal, isFalse);
    await controller.refreshActivity();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceActivityContent(
            controller: controller,
            onOpen: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Delegated research'), findsOneWidget);
  });

  testWidgets('idle parent with active child has a menu spinner', (
    tester,
  ) async {
    startChild();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileChatIndicator(chat: chat, row: const {}),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  for (final terminalStatus in [
    'completed',
    'failed',
    'timeout',
    'cancelled',
  ]) {
    testWidgets('last child $terminalStatus clears ongoing indicators', (
      tester,
    ) async {
      chat.status = ProfileTurnStatus.completed;
      startChild();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Column(
                children: [
                  ProfileChatIndicator(chat: chat, row: const {}),
                  Expanded(
                    child: WorkspaceActivityContent(
                      controller: controller,
                      onOpen: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Delegated research'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(chat.busy, isFalse);

      host.event('a', 'subagent.complete', {
        'subagent_id': 'child',
        'status': terminalStatus,
      });
      await tester.pump();
      expect(find.text('Delegated research'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(chat.status, ProfileTurnStatus.completed);
    });
  }

  test('one completed child does not hide a remaining active child', () {
    startChild();
    host.event('a', 'subagent.start', {'subagent_id': 'second'});
    host.event('a', 'subagent.complete', {
      'subagent_id': 'child',
      'status': 'timeout',
    });
    expect(
      controller.liveActivity.single.state,
      ProfileLiveActivityState.running,
    );
  });

  testWidgets('input request retains priority over active children', (
    tester,
  ) async {
    startChild();
    host.event('a', 'clarify', {'question': 'Which folder?'});
    expect(
      controller.liveActivity.single.state,
      ProfileLiveActivityState.needsInput,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileChatIndicator(chat: chat, row: const {}),
        ),
      ),
    );
    expect(find.byTooltip('Input needed'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test('main turn appears before the server snapshot catches up', () async {
    chat.draft = 'Start research';
    await controller.send(chat);
    await controller.refreshActivity();
    expect(
      controller.liveActivity.single.state,
      ProfileLiveActivityState.running,
    );
  });

  test('same chat IDs in different profiles retain their owners', () async {
    startChild();
    await controller.switchProfile('b');
    final other = await controller.openSession(
      ProfileSessionKey(controller.current!.scope, chat.key.sessionId),
    );
    expect(other!.key.sessionId, chat.key.sessionId);
    host.event('b', 'subagent.start', {'subagent_id': 'child'});
    expect(
      controller.liveActivity.map((item) => item.workspace.profileName),
      unorderedEquals(['a', 'b']),
    );
    host.event('a', 'subagent.complete', {
      'subagent_id': 'child',
      'status': 'completed',
    });
    expect(controller.liveActivity.single.workspace.profileName, 'b');
  });

  test('local and server activity merge into one row', () async {
    controller.dispose();
    final snapshotHost = ActivityHost();
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'ongoing-activity',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: snapshotHost.gateway,
    );
    await controller.initialize();
    final local = await controller.createChat();
    local.status = ProfileTurnStatus.running;
    snapshotHost.live.add({
      'id': local.runtimeId,
      'session_key': local.key.sessionId,
      'status': 'working',
      'side_tasks_running': 2,
    });
    await controller.refreshActivity();
    expect(controller.liveActivity, hasLength(1));
    expect(controller.liveActivity.single.sideTasksRunning, 2);
  });
}
