import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/server_connection_status.dart';
import 'package:wing/core/services/workspace_snapshot_store.dart';
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  testWidgets(
    'cold notification retains cached reading and draft while offline',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final host = Host()..running = false;
      final connection = SavedConnection(
        id: 'claw',
        label: 'Claw',
        host: 'unused',
        port: 1,
        apiKey: '',
      );
      ProfileWorkspaceController owner(String identity) =>
          ProfileWorkspaceController(
            connection: connection,
            connectionIdentity: identity,
            preferences: preferences,
            gatewayFactory: host.gateway,
          );
      var controller = owner('verified');
      final starting = controller.initialize();
      await tester.pump();
      await starting;
      final chat = await controller.createChat();
      final key = chat.key;
      await controller.updateDraft(chat, 'My unsent thought');
      expect(chat.messages.single['content'], 'a completed');
      controller.dispose();
      controller = owner('verified');
      expect(controller.current!.sessions, isNotEmpty);
      expect(
        controller.connectionStatus.phase,
        ServerConnectionPhase.unchecked,
      );
      host.discoveryFailure = const SocketException(
        'Failed host lookup: private.host',
      );
      await controller.openNotification(key);
      expect(
        controller.notificationChat!.messages.single['content'],
        'a completed',
      );
      expect(controller.notificationChat!.draft, 'My unsent thought');
      expect(controller.notificationChat!.offlineSnapshot, isTrue);
      expect(controller.notificationChat!.opening, isTrue);
      expect(controller.error, isNull);
      expect(
        controller.connectionStatus.phase,
        ServerConnectionPhase.reconnecting,
      );
      await controller.send(controller.notificationChat!);
      expect(host.calls.where((c) => c.$2 == 'prompt.submit'), isEmpty);
      for (final seconds in [1, 2, 4, 8, 16]) {
        await tester.pump(Duration(seconds: seconds));
      }
      expect(
        controller.connectionStatus.phase,
        ServerConnectionPhase.disconnected,
      );
      expect(controller.notificationChat!.key, key);
      final changedCredentials = owner('other-credentials');
      expect(changedCredentials.current, isNull);
      changedCredentials.dispose();
      host.discoveryFailure = null;
      final resuming = controller.resumeConnection();
      await tester.pump();
      await resuming;
      expect(controller.notificationChat, isNull);
      expect(controller.current!.chat!.key, key);
      expect(controller.current!.chat!.draft, 'My unsent thought');
      expect(controller.current!.chat!.offlineSnapshot, isFalse);
      expect(
        controller.connectionStatus.phase,
        ServerConnectionPhase.connected,
      );
      expect(host.calls.where((c) => c.$2 == 'prompt.submit'), isEmpty);
      controller.dispose();
    },
  );

  test(
    'oversized snapshots replace stale content and stay below the byte limit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = WorkspaceSnapshotStore(preferences, 'verified');
      await store.write({'selected': 'stale', 'profiles': []});
      await store.write({
        'selected': 'new',
        'profiles': [
          {
            'name': 'new',
            'sessions': [],
            'projects': [],
            'chats': [
              {
                'id': 'recent',
                'messages': List.generate(
                  100,
                  (i) => {'id': i, 'content': '語' * 10000},
                ),
              },
            ],
          },
        ],
      });
      final saved = store.read();
      expect(saved['selected'], 'new');
      expect(
        utf8.encode(jsonEncode(saved)).length,
        lessThanOrEqualTo(2 * 1024 * 1024),
      );
      final messages = saved['profiles'][0]['chats'][0]['messages'] as List;
      expect(messages.last['id'], 99);
    },
  );
}
