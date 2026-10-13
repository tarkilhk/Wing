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
    group = (await fixture.repository.groups(groupMessages: null)).single;
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
        observationComplete: true,
        scope: repository.scope,
        instance: repository.instance,
        id: group.id,
        name: group.name,
        members: group.members,
      );
      final reader = BotGroupHistorySession(repository, ownedGroup);
      addTearDown(reader.dispose);
      await reader.select(ownedGroup.members.first);
      expect(reader.reader.historyError, isNull);
      expect(reader.reader.messages.single['content'], 'Production snapshot');
      offline = true;
      await reader.refresh();
      expect(reader.reader.historyError, isNotNull);
      expect(reader.reader.messages.single['content'], 'Production snapshot');
      offline = false;
      await reader.refresh();
      expect(reader.reader.historyError, isNull);
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
      expect(session.reader.messages.length, 100);
      await session.loadOlder();
      expect(session.reader.messages.length, 102);
      expect(session.reader.messages.first['content'], 'Saved 1');
      expect((session.reader.nextHistoryOffset != null), isFalse);
      fixture.workerRows['atlas'] = [_worker('atlas-new')];
      await session.refresh();
      expect(fixture.historyReads.last, ('atlas', 'atlas-new-tip', 0));
      expect(fixture.commands, isEmpty);
    },
  );

  test(
    'absent, wrong-source and contradictory history stay distinct',
    () async {
      expect(session.historyAvailable, isFalse);
      fixture.workerRows['atlas'] = [];
      await session.select(group.members.first);
      expect(session.historyAvailable, isTrue);
      expect(session.reader.historyError, isNull);
      expect(fixture.historyReads, isEmpty);
      fixture.workerRows['atlas'] = [
        {..._worker('atlas'), 'source': 'cli'},
      ];
      await session.refresh();
      expect(session.reader.historyError, isNotNull);
      expect(session.historyAvailable, isTrue);
      expect(fixture.historyReads, isEmpty);
      fixture.workerRows['atlas'] = [_worker('atlas')];
      fixture.historyHook = (_, _, _) async => ProfileHistoryPage(
        'another-session',
        [_message(1, 'Private')],
        0,
        100,
      );
      await session.refresh();
      expect(session.reader.historyError, isNotNull);
      expect(session.reader.messages, isEmpty);
      fixture.historyHook = null;
      fixture.workerMessages['atlas'] = [_message(1, 'Recovered')];
      await session.refresh();
      expect(session.reader.historyError, isNull);
      expect(session.reader.messages.single['content'], 'Recovered');
      fixture.historyHook = (_, _, _) async => throw StateError('Offline');
      await session.refresh();
      expect(session.reader.historyError, isNotNull);
      expect(session.reader.messages.single['content'], 'Recovered');
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
      expect(session.historyAvailable, isFalse);
      final retiredReader = session.reader;
      retiredReader.recordScrollOffset(180);
      await session.select(group.members.last);
      expect(session.historyAvailable, isTrue);
      retiredReader.recordScrollOffset(420);
      expect(session.reader.historyScrollOffset, 0);
      expect(session.reader, isNot(same(retiredReader)));
      held.complete(
        ProfileHistoryPage('atlas-tip', [_message(1, 'Late Atlas')], 0, 100),
      );
      await first;
      expect(session.member?.profile, 'mira');
      expect(session.reader.messages.single['content'], 'Mira only');
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
