import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/profile_history_fixture.dart';

void main() {
  late ProfileHistoryFixture host;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = ProfileHistoryFixture();
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
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.openSession(
      ProfileSessionKey(controller.current!.scope, 'chat-0'),
    );
    chat = controller.current!.chat!;
    host.reads.clear();
  });

  test(
    'saved pages use the resolved chat identity and current profile',
    () async {
      chat.historySessionId = 'canonical-chat';
      final page = await controller.savedHistoryPage(chat);
      expect(page.sessionId, 'canonical-chat');
      expect(page.rows, hasLength(500));
      expect(host.reads.single.$1, 'sessions/canonical-chat/messages');
      expect(host.reads.single.$2, {
        'profile': 'personal',
        'limit': '500',
        'offset': '0',
        'order': 'latest',
        'include_compacted': 'true',
      });
    },
  );

  test('a saved page cannot cross into a different chat', () async {
    host.historySessionIdOverride = 'different';
    await expectLater(controller.savedHistoryPage(chat), throwsFormatException);
  });
}
