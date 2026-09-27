import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/models/session_visibility.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_browser_fixture.dart';

class TechnicalSessionsFixture extends ProfileBrowserFixture {
  bool oldTechnicalHistory = false;
  String technicalSource = 'oneshot';
  final extraRows = <Map<String, dynamic>>[];
  @override
  List<Map<String, dynamic>> searchRows(String profile, String query) => [
    for (final row in sessions(profile))
      if (row['id'] == query) {...row, 'session_id': row['id']},
  ];
  @override
  List<Map<String, dynamic>> sessions(String profile) => profile != 'personal'
      ? []
      : [
          ...extraRows,
          {
            'id': 'user-chat',
            'title': 'User conversation',
            'source': 'desktop',
            'profile': profile,
            'last_active': now - 120,
          },
          {
            'id': 'technical-run',
            'title': 'Technical command',
            'source': technicalSource,
            'parent_session_id': null,
            'profile': profile,
            'last_active': now - 60,
          },
        ];
  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    {
      'id': 1,
      'role': 'assistant',
      'content': 'Result',
      'timestamp':
          now - (oldTechnicalHistory && id == 'technical-run' ? 90000 : 60),
    },
  ];
}

void main() {
  test('Recents excludes the observed oneshot technical run', () async {
    SharedPreferences.setMockInitialValues({});
    final fixture = TechnicalSessionsFixture();
    final controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'technical-recents',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.refreshRecents();
    expect(controller.recentChats().map((chat) => chat.key.sessionId), [
      'user-chat',
    ]);
  });
  for (final running in [false, true]) {
    test('Recents excludes a loaded oneshot run (running=$running)', () async {
      SharedPreferences.setMockInitialValues({});
      final fixture = TechnicalSessionsFixture();
      final controller = ProfileWorkspaceController(
        connection: identityTestConnection(),
        connectionIdentity: 'loaded-technical',
        preferences: await SharedPreferences.getInstance(),
        gatewayFactory: fixture.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final resource = controller.current!;
      final chat = ProfileChat(
        key: ProfileSessionKey(resource.scope, 'technical-run'),
        runtimeId: 'technical-runtime',
        title: 'Technical command',
        source: 'oneshot',
      );
      chat.messages.add({
        'role': 'assistant',
        'content': 'Result',
        'timestamp': fixture.now,
      });
      if (running) chat.status = ProfileTurnStatus.running;
      resource.chats['technical-run'] = chat;
      expect(controller.recentChats(), isEmpty);
    });
  }
  test(
    'Recents excludes a remote live oneshot run with old messages',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fixture = TechnicalSessionsFixture()..oldTechnicalHistory = true;
      fixture.liveSessions['personal'] = [
        {
          'id': 'technical-runtime',
          'session_key': 'technical-run',
          'status': 'working',
          'last_active': fixture.now,
        },
      ];
      final controller = ProfileWorkspaceController(
        connection: identityTestConnection(),
        connectionIdentity: 'live-technical',
        preferences: await SharedPreferences.getInstance(),
        gatewayFactory: fixture.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.refreshRecents();
      expect(controller.recentChats().map((chat) => chat.key.sessionId), [
        'user-chat',
      ]);
    },
  );

  for (final source in ['cron', 'tool', 'subagent', 'kanban', 'oneshot']) {
    test(
      'Recents hides $source even with Show automated chats enabled',
      () async {
        SharedPreferences.setMockInitialValues({});
        final fixture = TechnicalSessionsFixture()..technicalSource = source;
        fixture.liveSessions['personal'] = [
          {
            'id': 'technical-runtime',
            'session_key': 'technical-run',
            'status': 'waiting',
            'last_active': fixture.now,
          },
        ];
        final controller = ProfileWorkspaceController(
          connection: identityTestConnection(),
          connectionIdentity: 'automation-$source',
          preferences: await SharedPreferences.getInstance(),
          gatewayFactory: fixture.gateway,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.setSessionVisibility(SessionVisibility.all);
        await controller.refreshRecents();
        expect(controller.liveActivity.single.source, source);
        expect(controller.recentChats().map((chat) => chat.key.sessionId), [
          'user-chat',
        ]);
        expect(
          fixture.reads.where(
            (read) => read.$1 == 'sessions/technical-run/messages',
          ),
          isEmpty,
        );
      },
    );
  }

  test(
    'Recents keeps interactive and custom sources, branches and parent background work',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fixture = TechnicalSessionsFixture();
      for (final source in ['cli', 'telegram', 'custom', 'unknown', null]) {
        fixture.extraRows.add({
          'id': 'chat-$source',
          'title': 'Conversation',
          'source': source,
          'profile': 'personal',
          'last_active': fixture.now - 60,
          'parent_session_id': 'user-chat',
        });
      }
      fixture.liveSessions['personal'] = [
        {
          'id': 'user-runtime',
          'session_key': 'user-chat',
          'status': 'idle',
          'side_tasks_running': 2,
          'last_active': fixture.now,
        },
      ];
      final controller = ProfileWorkspaceController(
        connection: identityTestConnection(),
        connectionIdentity: 'user-sources',
        preferences: await SharedPreferences.getInstance(),
        gatewayFactory: fixture.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.refreshRecents();
      expect(
        controller.recentChats().map((chat) => chat.key.sessionId),
        unorderedEquals([
          'user-chat',
          'chat-cli',
          'chat-telegram',
          'chat-custom',
          'chat-unknown',
          'chat-null',
        ]),
      );
      expect(
        controller
            .recentChats()
            .singleWhere((chat) => chat.key.sessionId == 'user-chat')
            .sideTasksRunning,
        2,
      );
    },
  );

  test(
    'a full page of internal sessions does not hide later recent chats',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fixture = TechnicalSessionsFixture();
      fixture.extraRows.addAll([
        for (var i = 0; i < 100; i++)
          {
            'id': 'internal-$i',
            'title': 'Internal',
            'source': 'oneshot',
            'profile': 'personal',
            'last_active': fixture.now,
          },
      ]);
      final controller = ProfileWorkspaceController(
        connection: identityTestConnection(),
        connectionIdentity: 'internal-page',
        preferences: await SharedPreferences.getInstance(),
        gatewayFactory: fixture.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.refreshRecents();
      expect(controller.recentChats().map((chat) => chat.key.sessionId), [
        'user-chat',
      ]);
      expect(
        fixture.reads.any(
          (read) => read.$1 == 'sessions' && read.$2['offset'] == '100',
        ),
        isTrue,
      );
    },
  );
}
