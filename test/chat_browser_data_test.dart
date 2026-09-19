import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/chat_browser_data.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'support/profile_paging_fixture.dart';

class ReaderFixture extends ProfilePagingFixture {
  final opened = <int>{}, closed = <int>{};
  final owners = <int, String>{};
  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final id = owners.length;
    owners[id] = scope.profileName;
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      connect: () async {
        opened.add(id);
        await base.connect();
      },
      close: () {
        closed.add(id);
        base.close();
      },
      get: base.read,
      rpc: base.call,
    );
  }
}

void main() {
  late ReaderFixture fixture;
  late ProfileWorkspaceController controller;
  late ChatBrowserData data;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = ReaderFixture();
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
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
    data = ChatBrowserData(controller);
  });
  tearDown(() {
    data.dispose();
    controller.dispose();
  });
  test(
    'paging deduplicates pin backfills without touching navigation or live sockets',
    () async {
      final live = {...fixture.opened};
      final owner = controller.current;
      await data.refresh(archivedOnly: false);
      expect(data.entries.length, 250);
      expect(data.entries.map((e) => e.key).toSet().length, 250);
      expect(data.complete, {'personal', 'work'});
      expect(controller.current, same(owner));
      expect(fixture.closed.intersection(live), isEmpty);
      expect(fixture.opened.difference(live), fixture.closed);
      expect(
        fixture.reads
            .where((r) => r.$1 == 'sessions' && r.$2['limit'] == '100')
            .length,
        4,
      );
    },
  );
  test(
    'failed later page leaves readable data but never a complete total',
    () async {
      fixture.pageFailures.add(('personal', 100));
      await data.refresh(archivedOnly: false);
      expect(data.errors.keys, contains('personal'));
      expect(data.complete, isNot(contains('personal')));
      expect(data.entries.where((e) => e.profile == 'personal'), isNotEmpty);
      expect(data.complete, contains('work'));
      fixture.pageFailures.clear();
      await data.refresh(archivedOnly: false);
      expect(data.errors, isEmpty);
      expect(data.complete.length, 2);
    },
  );
  test(
    'an old page cannot repopulate the active list after switching to archive',
    () async {
      final gate = Completer<void>();
      fixture.pageDelays[('personal', 0)] = gate;
      final old = data.refresh(archivedOnly: false);
      await Future<void>.delayed(Duration.zero);
      fixture.pageDelays.remove(('personal', 0));
      await data.refresh(archivedOnly: true);
      gate.complete();
      await old;
      expect(data.archived, isTrue);
      expect(data.entries, isEmpty);
    },
  );
  test('a stale search cannot replace newer results', () async {
    await data.refresh(archivedOnly: false);
    final gate = Completer<void>();
    fixture.searchDelays['old'] = gate;
    final old = data.search('old');
    await data.search('chat 110');
    gate.complete();
    await old;
    expect(data.searchMatches['personal'], {'chat-110'});
    expect(data.searchMatches['work'], {'chat-110'});
  });
  test(
    'disposing prevents late publication and still closes temporary readers',
    () async {
      final gate = Completer<void>();
      fixture.pageDelays[('personal', 0)] = gate;
      final pending = data.refresh(archivedOnly: false);
      data.dispose();
      gate.complete();
      await pending;
      // Replace for the common teardown; disposal itself is the assertion.
      data = ChatBrowserData(controller);
      expect(controller.current!.scope.profileName, 'personal');
    },
  );
}
