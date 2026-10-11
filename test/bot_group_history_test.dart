import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/bots.dart';
import 'package:wing/core/services/bot_group_history_session.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'support/administration_fixture.dart';
import 'support/bots_fixture.dart';

Map<String, dynamic> _worker(String id) => {
  'id': '$id-root',
  'resolved_id': '$id-tip',
  'title': 'Group: room-1',
  'source': 'bot_room',
};

Map<String, dynamic> _message(int id, String text) => {
  'id': id,
  'role': 'assistant',
  'content': text,
  'timestamp': 1791756000.0,
};

void main() {
  late BotsFixture fixture;
  late BotGroup group;
  late BotGroupHistorySession session;
  setUp(() async {
    fixture = BotsFixture();
    group = (await fixture.repository.groups()).single;
    session = BotGroupHistorySession(fixture.repository, group);
    fixture.workerRows['atlas'] = [_worker('atlas')];
    fixture.workerRows['mira'] = [_worker('mira')];
  });
  tearDown(() => session.dispose());

  test(
    'production viewer reads only the member profile with no runtime fallback',
    () async {
      final server = AdministrationFixture();
      var offline = false;
      server.rpcOverride = (method, params) async {
        expect(method, 'session.list');
        expect(params['profile'], 'atlas');
        expect(params['title'], 'Group: room-1');
        expect(params['include_hidden'], isTrue);
        return {
          'sessions': [_worker('atlas')],
        };
      };
      server.override = (method, path, query, body) async {
        expect(method, 'GET');
        if (path == 'profiles') return {'profiles': fixture.profiles};
        if (path == 'profiles/active') {
          return {'current': 'atlas', 'active': 'atlas'};
        }
        expect(path, 'sessions/atlas-tip/messages');
        expect(query, {
          'profile': 'atlas',
          'limit': '100',
          'offset': '0',
          'order': 'latest',
          'include_compacted': 'true',
          'inline_images': 'false',
        });
        if (offline) throw DashboardSessionNotFound(path);
        return {
          'session_id': 'atlas-tip',
          'messages': [_message(1, 'Production snapshot')],
          'pagination': {
            'limit': 100,
            'offset': 0,
            'order': 'latest',
            'returned': 1,
          },
        };
      };
      final repository = BotsRepository.forServer(server.server);
      final ownedGroup = BotGroup(
        scope: repository.scope,
        instance: repository.instance,
        id: group.id,
        name: group.name,
        members: group.members,
      );
      final reader = BotGroupHistorySession(repository, ownedGroup);
      addTearDown(reader.dispose);
      await reader.select(ownedGroup.members.first);
      expect(reader.error, isNull);
      expect(reader.messages.single.text, 'Production snapshot');
      offline = true;
      await reader.refresh();
      expect(reader.error, isNotNull);
      expect(reader.messages.single.text, 'Production snapshot');
      offline = false;
      await reader.refresh();
      expect(reader.error, isNull);
      expect(
        server.rpcRequests.every((read) => read == ('atlas', 'session.list')),
        isTrue,
      );
      expect(server.requests.every((read) => read.$1 == 'GET'), isTrue);
    },
  );

  test(
    'exact hidden worker tip, paged history and refresh issue no commands',
    () async {
      final registry = <(String, Map<String, dynamic>)>[];
      fixture.readHook = (profile, method, params) async {
        if (method == 'session.list') registry.add((profile, params));
        return null;
      };
      fixture.workerMessages['atlas'] = [
        for (var id = 1; id <= 102; id++) _message(id, 'Saved $id'),
      ];
      await session.select(group.members.first);
      expect(registry.single.$1, 'atlas');
      expect(registry.single.$2, {
        'title': 'Group: room-1',
        'include_hidden': true,
      });
      expect(fixture.historyReads.single, ('atlas', 'atlas-tip', 0));
      expect(session.messages.length, 100);
      await session.loadOlder();
      expect(session.messages.length, 102);
      expect(session.messages.first.text, 'Saved 1');
      expect(session.hasOlder, isFalse);
      fixture.workerRows['atlas'] = [_worker('atlas-new')];
      await session.refresh();
      expect(fixture.historyReads.last, ('atlas', 'atlas-new-tip', 0));
      expect(fixture.commands, isEmpty);
    },
  );

  test(
    'absent, wrong-source and contradictory history stay distinct',
    () async {
      fixture.workerRows['atlas'] = [];
      await session.select(group.members.first);
      expect(session.error, isNull);
      expect(fixture.historyReads, isEmpty);
      fixture.workerRows['atlas'] = [
        {..._worker('atlas'), 'source': 'cli'},
      ];
      await session.refresh();
      expect(session.error, isNotNull);
      expect(fixture.historyReads, isEmpty);
      fixture.workerRows['atlas'] = [_worker('atlas')];
      fixture.historyHook = (_, _, _) async => ProfileHistoryPage(
        'another-session',
        [_message(1, 'Private')],
        0,
        100,
      );
      await session.refresh();
      expect(session.error, isNotNull);
      expect(session.messages, isEmpty);
      fixture.historyHook = null;
      fixture.workerMessages['atlas'] = [_message(1, 'Recovered')];
      await session.refresh();
      expect(session.error, isNull);
      expect(session.messages.single.text, 'Recovered');
      fixture.historyHook = (_, _, _) async => throw StateError('Offline');
      await session.refresh();
      expect(session.error, isNotNull);
      expect(session.messages.single.text, 'Recovered');
    },
  );

  test(
    'late pages cannot cross bot selection or resurrect a disposed route',
    () async {
      final held = Completer<ProfileHistoryPage>();
      fixture.historyHook = (profile, id, offset) async => profile == 'atlas'
          ? held.future
          : ProfileHistoryPage(id, [_message(2, 'Mira only')], offset, 100);
      final first = session.select(group.members.first);
      await Future<void>.delayed(Duration.zero);
      await session.select(group.members.last);
      held.complete(
        ProfileHistoryPage('atlas-tip', [_message(1, 'Late Atlas')], 0, 100),
      );
      await first;
      expect(session.member?.profile, 'mira');
      expect(session.messages.single.text, 'Mira only');
      final disposing = Completer<ProfileHistoryPage>();
      fixture.historyHook = (_, _, _) => disposing.future;
      final pending = session.refresh();
      await Future<void>.delayed(Duration.zero);
      session.dispose();
      // Replace the teardown owner; the retired owner must never emit again.
      session = BotGroupHistorySession(fixture.repository, group);
      disposing.complete(
        ProfileHistoryPage('mira-tip', [_message(3, 'Late')], 0, 100),
      );
      await pending;
      expect(fixture.commands, isEmpty);
    },
  );

  test('foreign group and non-member cannot read a worker', () async {
    const member = BotGroupMember(
      id: 'foreign',
      profile: 'forge',
      handle: 'bot_forge',
      name: 'Forge',
    );
    await expectLater(
      fixture.repository.groupMemberSession(group, member),
      throwsStateError,
    );
    await expectLater(
      fixture.repository.groupMemberHistory(group, member, 'forge-tip', 0),
      throwsArgumentError,
    );
    expect(fixture.historyReads, isEmpty);
  });
}
