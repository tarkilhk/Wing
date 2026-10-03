import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/chat_browser_data.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

import 'support/browser_mutations_fixture.dart';

void main() {
  late BrowserMutationsFixture host;
  late ProfileWorkspaceController controller;
  late ChatBrowserData data;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = BrowserMutationsFixture()..extraRows = 110;
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Test',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'mutations',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    data = ChatBrowserData(controller);
    await data.refresh(archivedOnly: false);
  });
  tearDown(() {
    data.dispose();
    controller.dispose();
  });

  ProfileSessionKey key(String id) =>
      ProfileSessionKey(controller.current!.scope, id);
  Map<String, dynamic> row(String id) =>
      data.entries.firstWhere((e) => e.sessionKey == key(id)).row;

  test(
    'confirmed changes outside the owner page publish before background reads',
    () async {
      expect(
        controller.current!.sessions.any((r) => r['id'] == 'extra-100'),
        isFalse,
      );
      final gate = Completer<void>();
      host.pageDelays[('personal', 0)] = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await controller.mutateSession(
        key('extra-100'),
        changes: {'pinned': true},
      );
      expect(row('extra-100')['pinned'], isTrue);
      expect(row('extra-100')['input_tokens'], 1000);
      expect(data.hasCompleteSnapshot('personal'), isTrue);
      gate.complete();
      await data.refresh(archivedOnly: false);
      expect(row('extra-100')['pinned'], isTrue);
    },
  );

  test(
    'overlapping refreshes cannot roll back a newer confirmed action',
    () async {
      final gate = Completer<void>();
      host.pageDelays[('personal', 0)] = gate;
      final refresh = data.refresh(archivedOnly: false);
      await Future<void>.delayed(Duration.zero);
      await controller.mutateSession(key('newest'), changes: {'pinned': true});
      await controller.mutateSession(
        key('newest'),
        changes: {'title': 'New title'},
      );
      final observations = <(Object?, Object?)>[];
      void changed() =>
          observations.add((row('newest')['pinned'], row('newest')['title']));
      data.addListener(changed);
      gate.complete();
      await refresh;
      data.removeListener(changed);
      expect(observations, isNotEmpty);
      expect(observations.every((r) => r == (true, 'New title')), isTrue);
      expect(
        host.updates,
        hasLength(2),
        reason: 'refreshes never replay writes',
      );
    },
  );

  test(
    'refresh failure retains confirmed changes and retry only rereads',
    () async {
      host.pageFailures.add(('personal', 0));
      await controller.mutateSession(
        key('extra-100'),
        changes: {'archived': true},
      );
      await data.refresh(archivedOnly: false);
      expect(
        data.entries.any((e) => e.sessionKey == key('extra-100')),
        isFalse,
      );
      expect(data.errors['personal'], contains('Could not refresh chats'));
      expect(data.hasCompleteSnapshot('personal'), isTrue);
      host.pageFailures.clear();
      await data.refresh(archivedOnly: false);
      expect(data.errors, isEmpty);
      expect(host.updates, hasLength(1));
      expect(
        data.entries.any((e) => e.sessionKey == key('extra-100')),
        isFalse,
      );
    },
  );

  test(
    'project edits, moves, creation and deletion use the same refresh lifecycle',
    () async {
      final gate = Completer<void>();
      host.projectReadDelay = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final owner = controller.current!;
      await controller.updateProject(
        owner.scope,
        'p2',
        name: 'Renamed project',
        color: '#112233',
      );
      expect(
        data.projectRows('personal').firstWhere((p) => p['id'] == 'p2')['name'],
        'Renamed project',
      );
      await controller.moveSessionToProject(
        key('extra-100'),
        owner.projects.firstWhere((p) => p['id'] == 'p2'),
      );
      expect(
        data.entries
            .firstWhere((e) => e.sessionKey == key('extra-100'))
            .project!['name'],
        'Renamed project',
      );
      await controller.createProject('New project', '/new');
      expect(
        data.projectRows('personal').any((p) => p['id'] == 'created'),
        isTrue,
      );
      await controller.deleteProject(owner.scope, 'p2');
      expect(data.projectRows('personal').any((p) => p['id'] == 'p2'), isFalse);
      expect(
        data.entries
            .firstWhere((e) => e.sessionKey == key('extra-100'))
            .project,
        isNull,
      );
      gate.complete();
      await data.refresh(archivedOnly: false);
      expect(data.projectRows('personal').any((p) => p['id'] == 'p2'), isFalse);
      expect(data.errors, isEmpty);
    },
  );

  test(
    'active message search remains available through mutation refresh',
    () async {
      await data.search('setup guide');
      expect(data.searchMatches['personal'], contains('old'));
      final gate = Completer<void>();
      host.pageDelays[('personal', 0)] = gate;
      await controller.mutateSession(key('old'), changes: {'pinned': true});
      expect(data.searchMatches['personal'], contains('old'));
      gate.complete();
      await data.refresh(archivedOnly: false);
      expect(data.searchMatches['personal'], contains('old'));
      expect(data.searching, isFalse);
    },
  );

  test(
    'new chats immediately acquire their confirmed project membership',
    () async {
      final gate = Completer<void>();
      host.pageDelays[('personal', 0)] = gate;
      final project = controller.current!.projects.firstWhere(
        (p) => p['id'] == 'p2',
      );
      final chat = await controller.createChat(inProject: project);
      expect(
        data.entries
            .firstWhere((entry) => entry.sessionKey == chat.key)
            .project!['id'],
        'p2',
      );
      gate.complete();
      await data.refresh(archivedOnly: false);
      expect(data.entries.any((entry) => entry.sessionKey == chat.key), isTrue);
      expect(
        data.entries
            .firstWhere((entry) => entry.sessionKey == chat.key)
            .project!['id'],
        'p2',
      );
    },
  );
}
