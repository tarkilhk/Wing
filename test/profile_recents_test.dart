import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_browser_fixture.dart';

class _RecentsFixture extends ProfileBrowserFixture {
  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    if (id != 'empty')
      {
        'id': 1,
        'role': 'assistant',
        'content': 'Saved reply',
        'timestamp': id == 'heartbeat'
            ? now - 90000
            : sessions(profile)
                      .where((row) => row['id'] == id)
                      .firstOrNull?['last_active'] ??
                  now - 90000,
      },
  ];
  @override
  List<Map<String, dynamic>> sessions(String profile) => [
    for (final id in ['empty', 'heartbeat'])
      {'id': id, 'title': id, 'profile': profile, 'last_active': now},
    if (profile == 'personal')
      for (var i = 0; i < 105; i++)
        {
          'id': 'recent-$i',
          'title': 'Finished conversation $i',
          'profile': profile,
          'last_active': now - i * 60,
          'pinned': i == 0,
        },
    {
      'id': 'shared-id',
      'title': '$profile conversation',
      'profile': profile,
      'last_active': now - 600,
      'archived': profile == 'work',
    },
    {
      'id': 'old',
      'title': 'Old pinned chat',
      'profile': profile,
      'last_active': now - 90000,
      'pinned': true,
    },
  ];
}

void main() {
  late _RecentsFixture fixture;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;
  late SharedPreferences preferences;

  ProfileWorkspaceController makeController({String identity = 'recents'}) =>
      ProfileWorkspaceController(
        access: ConnectionAccess(
          connection: identityTestConnection(),
          dashboardOAuth: null,
        ),
        connectionIdentity: identity,
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: fixture.gateway,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    fixture = _RecentsFixture();
    controller = makeController();
    await controller.initialize();
  });
  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });

  test(
    'loads every recent page across profiles, including archived chats',
    () async {
      final selectedScope = controller.current!.scope;
      await controller.refreshRecents();
      final items = controller.recentChats();
      expect(items, hasLength(107));
      expect(items.map((item) => item.key).toSet(), hasLength(107));
      expect(
        items.where((item) => item.key.sessionId == 'shared-id'),
        hasLength(2),
      );
      expect(items.any((item) => item.key.sessionId == 'old'), isFalse);
      expect(items.first.key.sessionId, 'recent-0');
      expect(
        fixture.reads.where(
          (read) =>
              read.$1 == 'sessions/recent-0/messages' &&
              read.$2['limit'] == '1',
        ),
        hasLength(1),
      );
      expect(items.every((item) => item.state == null), isTrue);
      expect(controller.current!.scope, selectedScope);
      expect(controller.current!.chat, isNull);
      expect(
        fixture.calls.where((call) => call.$2 == 'session.resume'),
        isEmpty,
      );
      expect(
        fixture.reads.any(
          (read) =>
              read.$1 == 'sessions' &&
              read.$2['offset'] == '100' &&
              read.$2['archived'] == 'include',
        ),
        isTrue,
      );
    },
  );

  test(
    'rolling window expires idle chats without another network refresh',
    () async {
      await controller.refreshRecents();
      final newest = fixture.now;
      final boundary = DateTime.fromMillisecondsSinceEpoch(
        ((newest + 86400) * 1000).round(),
      );
      expect(
        controller.recentChats(now: boundary).map((item) => item.key.sessionId),
        ['recent-0'],
      );
      expect(
        controller.recentChats(now: boundary.add(const Duration(seconds: 1))),
        isEmpty,
      );
    },
  );

  test(
    'partial profile failure keeps available recent chats and reports the gap',
    () async {
      fixture.failWork = true;
      await controller.refreshRecents();
      expect(controller.recentChats(), hasLength(106));
      expect(controller.recentsAvailableProfiles, 1);
      expect(controller.recentsProfileErrors['work'], isNotNull);
    },
  );

  test('opening or drafting in an old chat does not make it recent', () async {
    final key = ProfileSessionKey(controller.current!.scope, 'old');
    final chat = await controller.openSession(key);
    await controller.updateDraft(chat!, 'Unsent draft');
    await controller.refreshRecents();
    expect(controller.recentChats().any((item) => item.key == key), isFalse);
    expect(
      preferences.getKeys().where((key) => key.startsWith('recent_visits_')),
      isEmpty,
    );
  });

  test(
    'empty chats and fresh heartbeats do not count as recent messages',
    () async {
      await controller.createChat(canDispatch: () => true);
      await controller.refreshRecents();
      expect(controller.recentChats(), hasLength(107));
      expect(
        controller.recentChats().any(
          (item) => ['empty', 'heartbeat'].contains(item.key.sessionId),
        ),
        isFalse,
      );
    },
  );

  test(
    'new local messages appear without opening or visit timestamps',
    () async {
      final chat = await controller.createChat(canDispatch: () => true);
      expect(controller.recentChats(), isEmpty);
      chat.reading.installSavedHistory([
        ...chat.reading.messages,
        {'role': 'user', 'content': 'Sent message', 'timestamp': fixture.now},
      ]);
      expect(controller.recentChats().single.key, chat.key);
      expect(
        controller.recentChats(
          now: DateTime.fromMillisecondsSinceEpoch(
            ((fixture.now + 86401) * 1000).round(),
          ),
        ),
        isEmpty,
      );
    },
  );

  test(
    'opens a recent archived chat in its owning profile with its saved title',
    () async {
      await controller.refreshRecents();
      final item = controller.recentChats().singleWhere(
        (item) => item.key.workspace.profileName == 'work',
      );
      final chat = await controller.openSession(item.key);
      expect(chat, isNotNull);
      expect(chat!.title, 'work conversation');
      expect(chat.archived, isTrue);
      expect(controller.current!.scope, item.key.workspace);
    },
  );
}
