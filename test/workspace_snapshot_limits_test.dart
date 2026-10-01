import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/workspace_snapshot_store.dart';

import 'profile_workspace_controller_test.dart' show Host;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'message limit uses encoded characters and excludes its boundary',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = WorkspaceSnapshotStore(preferences, 'message-limits');

      Map<String, dynamic> row(
        String id,
        int length, {
        String character = 'x',
      }) {
        final message = <String, dynamic>{'id': id, 'content': ''};
        final overhead = jsonEncode(message).length;
        message['content'] = character * (length - overhead);
        expect(jsonEncode(message).length, length);
        return message;
      }

      final messages = [
        row('below', 32767),
        row('boundary', 32768),
        row('above', 32769),
        row('multibyte', 32767, character: '語'),
        {'id': 'escaped', 'content': '\n' * 17000},
      ];
      final snapshot = <String, dynamic>{
        'profiles': [
          {
            'name': 'a',
            'chats': [
              {'id': 'chat', 'messages': messages},
            ],
          },
        ],
      };

      await store.write(snapshot);

      final saved = store.read()['profiles'][0]['chats'][0]['messages'] as List;
      expect(saved.map((message) => message['id']), ['below', 'multibyte']);
      expect(snapshot['profiles'][0]['chats'][0]['messages'], same(messages));
      expect(messages, hasLength(5));
    },
  );

  test(
    'large excluded metadata does not discard small reading content',
    () async {
      const storageKey = 'workspace_reading_v1_metadata-projection';
      final seed = jsonEncode({
        'selected': 'a',
        'profiles': [
          {
            'name': 'a',
            'sessions': [],
            'projects': [],
            'chats': [
              {'id': 'chat', 'title': 'Chat', 'messages': []},
            ],
          },
        ],
      });
      SharedPreferences.setMockInitialValues({storageKey: seed});
      final preferences = await SharedPreferences.getInstance();
      final controller = ProfileWorkspaceController(
        connection: SavedConnection(
          id: 'projection',
          label: 'Projection',
          host: 'unused',
          port: 1,
          apiKey: '',
        ),
        connectionIdentity: 'metadata-projection',
        preferences: preferences,
        gatewayFactory: Host().gateway,
      );
      final source = <String, dynamic>{
        'id': 7,
        'role': 'assistant',
        'content': 'Read this answer offline',
        'metadata': {'private': 'excluded private value ' * 2000},
      };
      expect(jsonEncode(source).length, greaterThan(32768));
      final chat = controller.current!.chats.values.single;
      chat.messages = [source];

      controller.dispose();
      await Future<void>(() async {
        while (true) {
          await preferences.reload();
          if (preferences.getString(storageKey) != seed) return;
          await Future<void>.delayed(Duration.zero);
        }
      }).timeout(const Duration(seconds: 10));

      final encoded = preferences.getString(storageKey)!;
      final saved =
          jsonDecode(encoded)['profiles'][0]['chats'][0]['messages'] as List;
      expect(saved, [
        {'id': 7, 'role': 'assistant', 'content': 'Read this answer offline'},
      ]);
      expect(encoded, isNot(contains('excluded private value')));
      expect(chat.messages.single, same(source));
      expect(source['metadata'], isNotNull);
    },
  );
}
