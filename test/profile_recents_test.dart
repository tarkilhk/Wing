import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'dart:async';
import 'package:wing/core/models/bots.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:wing/core/models/recent_conversation.dart';
import 'package:wing/core/models/session_visibility.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/workspace_recents_session.dart';
import 'package:wing/core/services/profile_gateway.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_browser_fixture.dart';
import 'support/bots_fixture.dart';

class _RecentsFixture extends ProfileBrowserFixture {
  bool unread = false;
  bool failDiscovery = false;
  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final delegate = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: () async {
        if (failDiscovery) throw http.ClientException('Discovery interrupted');
        return delegate.discover();
      },
      get: delegate.read,
      rpc: delegate.call,
      ownedPatch: (path, body, canDispatch, onDispatched) async {
        if (!canDispatch()) throw StateError('Read superseded');
        expect(path, 'sessions/shared-id');
        expect(body['profile'], scope.profileName);
        expect(body['unread'], false);
        onDispatched();
        unread = false;
        return {'ok': true};
      },
    );
  }

  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    if (id != 'empty' && id != 'active-empty')
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
    if (profile == 'personal')
      {
        'id': 'room-worker',
        'title': 'Group: room-uuid',
        'profile': profile,
        'source': 'bot_room',
        'last_active': now,
      },
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
      'unread': unread,
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
    'runtime heartbeats do not outrank newer messages or invent an age',
    () async {
      fixture.hiddenSessions['personal'] = [
        {
          'id': 'active-empty',
          'title': 'Empty active chat',
          'profile': 'personal',
        },
      ];
      fixture.liveSessions['personal'] = [
        {
          'id': 'busy-runtime',
          'session_key': 'recent-100',
          'status': 'working',
          'last_active': fixture.now + 1000,
        },
        {
          'id': 'empty-runtime',
          'session_key': 'active-empty',
          'status': 'working',
          'last_active': fixture.now + 2000,
        },
      ];
      await controller.refreshRecents();
      final chats = controller.recentChats();
      expect(chats.first.key.sessionId, 'recent-0');
      expect(chats.first.state, isNull);
      final busy = chats.singleWhere(
        (c) =>
            c.key.workspace.profileName == 'personal' &&
            c.key.sessionId == 'recent-100',
      );
      expect(busy.activity, isNotNull);
      expect(busy.lastActive, fixture.now - 6000);
      final empty = chats.singleWhere((c) => c.key.sessionId == 'active-empty');
      expect(empty.lastActive, 0);
      expect(chats.last.key, empty.key);
    },
  );

  test(
    'confirmed reading clears unread without advancing message freshness',
    () async {
      fixture.unread = true;
      await controller.refreshRecents();
      final before = controller.recentChats().singleWhere(
        (c) =>
            c.key.workspace.profileName == 'personal' &&
            c.key.sessionId == 'shared-id',
      );
      expect(before.unread, isTrue);
      await controller.openSession(before.key);
      final after = controller.recentChats().singleWhere(
        (c) => c.key == before.key,
      );
      expect(after.unread, isFalse);
      expect(after.lastActive, before.lastActive);
    },
  );

  test('group workers stay out of saved, opened and active Recents', () async {
    await controller.setSessionVisibility(SessionVisibility.all);
    await controller.refreshRecents();
    expect(
      controller.recentChats().any(
        (item) => item.key.sessionId == 'room-worker',
      ),
      isFalse,
    );
    expect(
      fixture.reads.any((read) => read.$1 == 'sessions/room-worker/messages'),
      isFalse,
    );
    final key = ProfileSessionKey(controller.current!.scope, 'room-worker');
    final chat = await controller.openSession(key);
    expect(chat?.source, 'bot_room');
    fixture.liveSessions[key.workspace.profileName] = [
      {
        'id': 'worker-runtime',
        'session_key': 'room-worker',
        'status': 'working',
      },
    ];
    await controller.refreshActivity();
    expect(
      controller.liveActivity.any((item) => item.sessionId == 'room-worker'),
      isTrue,
    );
    expect(
      controller.recentChats().any(
        (item) => item.key.sessionId == 'room-worker',
      ),
      isFalse,
    );
  });

  test(
    'cold passive canonical appearance loads before opening its chat',
    () async {
      await controller.refreshRecents();
      final keys = controller.recentChats().map((chat) => chat.key).toList();
      final target = keys.first;
      final botFixture = BotsFixture();
      final row = BotsFixture.profile(
        target.workspace.profileName,
        'Canonical assistant',
      );
      row['canonical_session'] = {
        'id': target.sessionId,
        'resolved_id': '${target.sessionId}-tip',
      };
      botFixture.profiles
        ..clear()
        ..add(row);
      final bots = BotsSession(
        (_) async => [
          BotsRepository(
            scope: controller.current!.scope,
            instance: 'Host',
            read: botFixture.read,
            savedHistory: botFixture.savedHistory,
            command: (_, _, _, _, _) async => throw StateError('Passive only'),
            ownership: (_, _) async => throw StateError('No runtime reads'),
          ),
        ],
      );
      addTearDown(bots.dispose);
      final activity = ValueNotifier<ChatNoticeActivity?>(null);
      addTearDown(activity.dispose);
      final visit = controller.recentConversationSession(
        onOpenGroup: (_) async {},
        entries: [
          for (final key in keys)
            RecentConversationEntry.chat(key: key, title: 'Saved title'),
        ],
        bots: bots,
        activity: activity,
      );
      addTearDown(visit.dispose);
      final calls = fixture.calls.length;
      visit.prepare(keys.take(3).map(RecentConversationKey.chat));
      await Future<void>.delayed(Duration.zero);
      expect(visit.cardAt(0).bot!.title, 'Canonical assistant');
      expect(visit.cardAt(0).bot!.describesConversation(target), isTrue);
      expect(fixture.calls.length, calls);
      expect(botFixture.commands, isEmpty);
      final reading = visit.cardAt(0).preview;
      final revision = visit.previewRevision(
            RecentConversationKey.chat(target),
          ),
          pixels = visit.cardRevision(RecentConversationKey.chat(target));
      row['ui_meta'] = {
        'hermes-bots': {'title': 'Renamed assistant'},
      };
      row['ui_meta_revisions'] = {'hermes-bots': 3};
      await bots.refresh();
      expect(
        visit.previewRevision(RecentConversationKey.chat(target)),
        revision,
      );
      expect(
        visit.cardRevision(RecentConversationKey.chat(target)),
        isNot(pixels),
      );
      expect(visit.cardAt(0).preview, same(reading));
      expect(visit.cardAt(0).bot!.title, 'Renamed assistant');
    },
  );

  test(
    'entry catalog anchors an old draft without changing recency or reopening',
    () async {
      await controller.refreshRecents();
      await controller.openSession(
        ProfileSessionKey(controller.current!.scope, 'old'),
      );
      final chat = controller.current!.chat!;
      await controller.updateDraft(chat, 'Unsent work');
      final activity = ValueNotifier<ChatNoticeActivity?>(null);
      final visit = controller.chatRecentConversationSession(
        onOpenGroup: (_) async {},
        bots: BotsSession((_) async => const []),
        chat: chat,
        activity: () => activity,
      );
      addTearDown(visit.dispose);
      addTearDown(activity.dispose);
      final resumes = fixture.calls
          .where((call) => call.$2 == 'session.resume')
          .length;
      expect(visit.modeEnabled, isFalse);
      expect(visit.selected, RecentConversationKey.chat(chat.key));
      visit.activate();
      await Future<void>.delayed(Duration.zero);
      expect(visit.entries.last.key, RecentConversationKey.chat(chat.key));
      expect(
        visit.entries.where((entry) => entry.key.chat == chat.key),
        hasLength(1),
      );
      expect(
        visit.entries.any(
          (entry) => entry.key.chat!.workspace.profileName == 'work',
        ),
        isTrue,
      );
      expect(
        controller.recentChats().any((item) => item.key == chat.key),
        isFalse,
      );
      expect(chat.composer.observation.displayedText, 'Unsent work');
      expect(
        fixture.calls.where((call) => call.$2 == 'session.resume'),
        hasLength(resumes),
      );
    },
  );

  test(
    'pinch catalog matches merged Recents freshness order including rooms',
    () async {
      final botFixture = BotsFixture();
      for (var seq = 1; seq <= 120; seq++) {
        botFixture.events.add({
          'room_id': 'room-1',
          'seq': seq,
          'kind': 'message.member',
          'created_at': fixture.now - 150 + seq,
          'actor': {'kind': 'member', 'id': 'atlas'},
          'payload': {'text': 'Group answer $seq'},
        });
      }
      final bots = BotsSession((_) async => [botFixture.repository]);
      addTearDown(bots.dispose);
      await bots.refresh();
      await controller.openSession(
        ProfileSessionKey(controller.current!.scope, 'recent-5'),
      );
      await controller.refreshRecents();
      final merged = WorkspaceRecentsSession(controller, bots);
      addTearDown(merged.dispose);
      final expected = merged
          .items()
          .map((item) => item.group?.name ?? item.chat!.title)
          .toList();
      expect(expected, contains('Research team'));
      final activity = ValueNotifier<ChatNoticeActivity?>(null);
      addTearDown(activity.dispose);
      BotGroup? openedGroup;
      final closeRoom = Completer<void>();
      final visit = controller.chatRecentConversationSession(
        onOpenGroup: (group) async {
          openedGroup = group;
          botFixture.room['name'] = 'Renamed research team';
          await bots.refresh();
          await closeRoom.future;
        },
        bots: bots,
        chat: controller.current!.chat!,
        activity: () => activity,
      );
      addTearDown(visit.dispose);
      visit.activate();
      await Future<void>.delayed(Duration.zero);
      expect(visit.catalogLoading, isFalse);
      expect(visit.entries.map((entry) => entry.title), expected);
      final room = visit.entries.singleWhere((entry) => entry.group != null);
      final selected = visit.selected;
      final revision = visit.previewRevision(room.key);
      final commands = List.of(botFixture.commands);
      final chatCalls = List.of(fixture.calls);
      expect(bots.groupReads.unread(room.group!), isTrue);
      visit.prepare([room.key]);
      await Future<void>.delayed(Duration.zero);
      final index = visit.entries.indexOf(room);
      expect(
        visit.cardAt(index).preview!.group!.messages.map((m) => m.text),
        List.generate(6, (i) => 'Group answer ${115 + i}'),
      );
      expect(
        visit.cardAt(index).preview!.group!.appearances.keys,
        contains('bot_atlas'),
      );
      expect(visit.previewRevision(room.key), revision);
      expect(bots.groupReads.unread(room.group!), isTrue);
      expect(botFixture.commands, commands);
      expect(fixture.calls, chatCalls);
      final opening = visit.select(room.key);
      await Future<void>.delayed(Duration.zero);
      expect(openedGroup?.key, room.key.group);
      expect(visit.selecting, isTrue);
      expect(visit.selected, selected);
      closeRoom.complete();
      expect(await opening, isTrue);
      expect(
        visit.entries.singleWhere((entry) => entry.key == room.key).title,
        'Renamed research team',
      );
      expect(visit.selected, selected);
      expect(controller.current!.chat!.key, selected!.chat);
      expect(botFixture.commands, commands);
    },
  );

  for (final heldMethod in ['session.active_list', 'profiles.get_asset']) {
    test(
      'cold Recents publishes groups while $heldMethod is pending',
      () async {
        final botFixture = BotsFixture();
        if (heldMethod == 'profiles.get_asset') {
          botFixture.profiles.first['has_avatar'] = true;
        }
        botFixture.events.add({
          'room_id': 'room-1',
          'seq': 1,
          'kind': 'message.member',
          'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
          'actor': {'kind': 'member', 'id': 'atlas'},
          'payload': {'text': 'Recent group answer'},
        });
        final started = Completer<void>(), release = Completer<void>();
        botFixture.readHook = (_, method, _) async {
          if (method == heldMethod) {
            if (!started.isCompleted) started.complete();
            await release.future;
            if (method == 'profiles.get_asset') return {'found': false};
          }
          return null;
        };
        final bots = BotsSession((_) async => [botFixture.repository]);
        final recents = WorkspaceRecentsSession(controller, bots);
        var published = false;
        recents.addListener(() {
          if (recents.items().any((item) => item.group != null)) {
            published = true;
          }
        });
        addTearDown(() async {
          release.complete();
          await Future<void>.delayed(Duration.zero);
          recents.dispose();
          bots.dispose();
        });
        recents.setVisible(true);
        await started.future;
        await Future<void>.delayed(Duration.zero);
        expect(recents.items().where((item) => item.chat != null), isNotEmpty);
        expect(
          recents.items().map((item) => item.group?.name),
          contains('Research team'),
          reason: 'Group discovery must not wait for unrelated bot reads',
        );
        expect(published, isTrue);
        expect(bots.state.loading, isTrue);
        expect(botFixture.commands, isEmpty);
      },
    );
  }

  test(
    'pinch publishes ready neighbors while bot refresh is pending',
    () async {
      await controller.openSession(
        ProfileSessionKey(controller.current!.scope, 'recent-5'),
      );
      final botFixture = BotsFixture();
      final started = Completer<void>(), release = Completer<void>();
      botFixture.readHook = (_, method, _) async {
        if (method == 'session.active_list') {
          started.complete();
          await release.future;
        }
        return null;
      };
      final bots = BotsSession((_) async => [botFixture.repository]);
      final activity = ValueNotifier<ChatNoticeActivity?>(null);
      final visit = controller.chatRecentConversationSession(
        onOpenGroup: (_) async {},
        bots: bots,
        chat: controller.current!.chat!,
        activity: () => activity,
      );
      addTearDown(() async {
        release.complete();
        await Future<void>.delayed(Duration.zero);
        visit.dispose();
        activity.dispose();
        bots.dispose();
      });
      visit.activate();
      await started.future;
      await controller.refreshRecents();
      expect(visit.catalogLoading, isTrue);
      expect(
        visit.entries.length,
        greaterThan(1),
        reason:
            'Ready chats must reach screenshot preparation before bot status',
      );
      expect(botFixture.commands, isEmpty);
    },
  );

  test('simultaneous Recents consumers share the physical refresh', () async {
    final delay = Completer<void>();
    fixture.pageDelays[('personal', 0)] = delay;
    Future<void>? observed;
    controller.addListener(() {
      if (controller.recentsLoading && observed == null) {
        observed = controller.refreshRecents();
      }
    });
    final first = controller.refreshRecents();
    final second = controller.refreshRecents();
    expect(identical(first, second), isTrue);
    expect(identical(first, observed), isTrue);
    delay.complete();
    await first;
    expect(controller.recentsLoading, isFalse);
    expect(controller.recentChats(), isNotEmpty);
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

  test(
    'discovery failure retains chats and the next refresh clears its error',
    () async {
      await controller.refreshRecents();
      final previous = controller
          .recentChats()
          .map((chat) => chat.key)
          .toList();
      expect(previous, isNotEmpty);
      fixture.failDiscovery = true;
      await controller.refreshRecents();
      expect(
        controller.recentsProfileErrors['recents'],
        'Recent chats could not be loaded.',
      );
      expect(controller.recentChats().map((chat) => chat.key), previous);
      expect(controller.recentsLoading, isFalse);
      fixture.failDiscovery = false;
      await controller.refreshRecents();
      expect(controller.recentsProfileErrors, isEmpty);
      expect(controller.recentChats().map((chat) => chat.key), previous);
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
