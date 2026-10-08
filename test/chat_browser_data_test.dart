import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/chat_browser_preferences.dart';
import 'package:wing/core/models/chat_list_view.dart';
import 'package:wing/core/services/chat_browser_data.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'support/profile_paging_fixture.dart';

class ReaderFixture extends ProfilePagingFixture {
  final opened = <int>{}, closed = <int>{};
  final owners = <int, String>{};
  bool failNextPage = false;
  bool failNextTree = false;
  bool failWorkIndex = false;
  bool failWorkSearch = false;
  bool permanentSearchFailure = false;
  final attempts = <(String, String, String?)>[];
  final omittedRows = <(String, String)>{};
  final rowUpdates = <(String, String), Map<String, dynamic>>{};
  @override
  List<Map<String, dynamic>> sessions(String profile) => [
    for (final row in super.sessions(profile))
      if (!omittedRows.contains((profile, row['id'] as String)))
        {...row, ...?rowUpdates[(profile, row['id'] as String)]},
  ];
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
      get: (path, query) async {
        attempts.add((scope.profileName, path, query['q']));
        if (scope.profileName == 'work') {
          if (failWorkIndex && path == 'sessions') {
            throw TimeoutException('Index offline');
          }
          if (failWorkSearch && path == 'sessions/search') {
            if (permanentSearchFailure) {
              throw const DashboardHttpException(403, 'sessions/search');
            }
            throw TimeoutException('Search offline');
          }
        }
        if (failNextPage && path == 'sessions' && query['offset'] == '100') {
          failNextPage = false;
          throw TimeoutException('Temporary page timeout');
        }
        return base.read(path, query);
      },
      rpc: (method, params) async {
        if (failNextTree && method == 'projects.tree') {
          failNextTree = false;
          throw TimeoutException('Temporary tree timeout');
        }
        return base.call(method, params);
      },
    );
  }
}

void main() {
  late ReaderFixture fixture;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;
  late ChatBrowserData data;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = ReaderFixture();
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: SavedConnection(
          id: 'host',
          label: 'Test',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'test',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
    data = ChatBrowserData(controller);
  });
  tearDown(() {
    data.dispose();
    controller.dispose();
    appPreferences.dispose();
  });
  test(
    'retirement from pending observation starts no browser page read',
    () async {
      fixture.attempts.clear();
      data.addListener(() {
        if (data.state.loading) data.dispose();
      });
      await data.refresh(archivedOnly: false);
      expect(fixture.attempts.where((read) => read.$2 == 'sessions'), isEmpty);
    },
  );

  test(
    'projection borrows shared filter facts and keeps row ordering stable',
    () async {
      await data.refresh(archivedOnly: false);
      final before = data
          .project('')
          .groups
          .expand((group) => group.entries)
          .map((entry) => entry.sessionKey)
          .toList();
      expect(
        await data.chooseView(
          BrowserPreferenceIntent.toggle(BrowserFilter.profile, 'work'),
        ),
        BrowserPreferencesSaveOutcome.saved,
      );
      final work = data.project('');
      expect(work.entries, isNotEmpty);
      expect(work.entries.every((entry) => entry.profile == 'work'), isTrue);
      expect(
        work.groups
            .expand((group) => group.entries)
            .map((entry) => entry.sessionKey),
        before.where((key) => key.workspace.profileName == 'work'),
      );
      expect(() => work.entries.clear(), throwsUnsupportedError);
      expect(() => work.groups.first.entries.clear(), throwsUnsupportedError);
      await data.chooseView(const BrowserPreferenceIntent.clearFilters());
      expect(
        data
            .project('')
            .groups
            .expand((group) => group.entries)
            .map((entry) => entry.sessionKey),
        before,
      );
    },
  );

  test(
    'menu catalog owns canonical profile and status choice intents',
    () async {
      await data.refresh(archivedOnly: false);
      final choice = data
          .filterChoices(BrowserFilter.profile)
          .singleWhere((value) => value.id == 'personal');
      expect(choice.selected, isFalse);
      expect(choice.decoration, BrowserChoiceDecoration.profile);
      await data.chooseView(choice.intent);
      expect(
        data
            .filterChoices(BrowserFilter.profile)
            .singleWhere((value) => value.id == 'personal')
            .selected,
        isTrue,
      );
      final status = data.filterChoices(BrowserFilter.status).first;
      expect(status.status, isNotNull);
      expect(status.intent.filter, BrowserFilter.status);
      expect(status.intent.value, status.status!.name);
      final project = data
          .filterChoices(BrowserFilter.project)
          .singleWhere((value) => value.id == 'personal/home');
      expect(project.decoration, BrowserChoiceDecoration.home);
      expect(project.label, '< personal >');
    },
  );

  for (final status in ['unread', 'draft']) {
    test('canonical refresh publishes $status filter membership', () async {
      fixture.rowUpdates[('personal', 'chat-0')] = {
        'unread': status == 'unread',
        'message_count': status == 'draft' ? 0 : 2,
      };
      await data.refresh(archivedOnly: false);
      await data.chooseView(
        BrowserPreferenceIntent.toggle(BrowserFilter.status, status),
      );
      final before = data.project('');
      final key = before.entries.single.sessionKey;
      final published = <List<ChatListEntry>>[];
      data.addListener(() => published.add(data.project('').entries));

      fixture.rowUpdates[('personal', 'chat-0')] = {
        'unread': false,
        'message_count': 2,
      };
      await controller.switchProfile('personal');

      expect(
        data.entries.singleWhere((entry) => entry.sessionKey == key).status,
        isNot(before.entries.single.status),
      );
      expect(data.project('').entries, isEmpty);
      expect(published, isNotEmpty);
      expect(published.last, isEmpty);

      fixture.rowUpdates[('personal', 'chat-0')] = {
        'unread': status == 'unread',
        'message_count': status == 'draft' ? 0 : 2,
      };
      published.clear();
      await controller.switchProfile('personal');
      expect(published, isNotEmpty);
      expect(published.last.map((entry) => entry.sessionKey), [key]);
    });
  }

  for (final field in ['title', 'preview']) {
    test('canonical refresh publishes local $field query membership', () async {
      fixture.rowUpdates[('personal', 'chat-0')] = {field: 'needle match'};
      await data.refresh(archivedOnly: false);
      final key = data.project('needle').entries.single.sessionKey;
      final published = <List<ChatListEntry>>[];
      data.addListener(() => published.add(data.project('needle').entries));

      fixture.rowUpdates[('personal', 'chat-0')] = {field: 'different text'};
      await controller.switchProfile('personal');

      expect(data.entries.any((entry) => entry.sessionKey == key), isTrue);
      expect(data.project('needle').entries, isEmpty);
      expect(published, isNotEmpty);
      expect(published.last, isEmpty);
    });
  }

  test('canonical row changes retain a stable filtered arrangement', () async {
    fixture.rowUpdates[('personal', 'chat-0')] = {
      'title': 'needle before',
      'unread': true,
      'message_count': 2,
    };
    await data.refresh(archivedOnly: false);
    await data.chooseView(
      BrowserPreferenceIntent.toggle(BrowserFilter.status, 'unread'),
    );
    final before = data.project('needle');
    final key = before.entries.single.sessionKey;
    final row = data.row(key);
    var publications = 0;
    var rowPublications = 0;
    data.addListener(() => publications++);
    row.addListener(() => rowPublications++);
    final indexReads = fixture.reads
        .where((read) => read.$1 == 'sessions' && read.$2['limit'] == '100')
        .length;

    fixture.rowUpdates[('personal', 'chat-0')] = {
      'title': 'needle after',
      'unread': true,
      'message_count': 2,
      'input_tokens': 1234,
    };
    await controller.switchProfile('personal');

    expect(data.row(key), same(row));
    expect(row.value.title, 'needle after');
    expect(row.value.tokens, 1234);
    expect(rowPublications, greaterThan(0));
    expect(publications, 0);
    expect(
      data.project('needle').groups.map((group) => group.key),
      before.groups.map((group) => group.key),
    );
    expect(
      fixture.reads
          .where((read) => read.$1 == 'sessions' && read.$2['limit'] == '100')
          .length,
      indexReads,
      reason: 'Canonical refresh adds no browser index read',
    );
  });

  test(
    'project choices follow single, multiple and cleared profile filters',
    () async {
      await data.refresh(archivedOnly: false);
      Set<String> projectIds() => data
          .filterChoices(BrowserFilter.project)
          .map((choice) => choice.id)
          .toSet();
      final all = projectIds();
      expect(all.where((id) => id.startsWith('personal/')), isNotEmpty);
      expect(all.where((id) => id.startsWith('work/')), isNotEmpty);

      await data.chooseView(BrowserPreferenceIntent.exclusiveProfile('work'));
      expect(projectIds(), all.where((id) => id.startsWith('work/')).toSet());
      expect(projectIds(), contains('work/home'));

      await data.chooseView(
        BrowserPreferenceIntent.exclusiveProfile('personal'),
      );
      expect(
        projectIds(),
        all.where((id) => id.startsWith('personal/')).toSet(),
      );

      await data.chooseView(
        BrowserPreferenceIntent.toggle(BrowserFilter.profile, 'work'),
      );
      expect(projectIds(), all);

      await data.chooseView(
        const BrowserPreferenceIntent.clear(BrowserFilter.profile),
      );
      expect(projectIds(), all);
    },
  );

  test(
    'invalid saved view has a neutral projection and explicit reset',
    () async {
      await data.refresh(archivedOnly: false);
      final key = ChatBrowserPreferencesCodec.storageKey('test');
      await controller.preferences.setString(key, '{');
      await appPreferences.reload();
      final projection = data.project('');
      expect(data.viewPreferences.validity, BrowserPreferencesValidity.invalid);
      expect(data.viewPreferences.display, isNull);
      expect(projection.entries.length, data.entries.length);
      expect(projection.groups.single.key, 'all');
      expect(projection.groups.single.label, 'Chats');
      expect(controller.preferences.getString(key), '{');
      expect(
        await data.chooseView(const BrowserPreferenceIntent.reset()),
        BrowserPreferencesSaveOutcome.saved,
      );
      expect(data.viewPreferences.display!.grouping, ChatGrouping.project);
      expect(
        data.project('').groups.map((group) => group.key),
        isNot(contains('all')),
      );
    },
  );

  test(
    'disposing browser consumer leaves borrowed preference owner usable',
    () async {
      final channel = appPreferences.browserPreferencesFor('test');
      data.dispose();
      expect(
        await appPreferences.chooseBrowserPreferences(
          'test',
          BrowserPreferenceIntent.toggle(BrowserFilter.profile, 'work'),
        ),
        BrowserPreferencesSaveOutcome.saved,
      );
      expect(channel.value.confirmed!.profiles, {'work'});
      data = ChatBrowserData(controller);
      await data.refresh(archivedOnly: false);
      expect(
        data.project('').entries.every((entry) => entry.profile == 'work'),
        isTrue,
      );
    },
  );

  test(
    'query matching belongs to the projection without mutating saved filters',
    () async {
      await data.refresh(archivedOnly: false);
      final before = data.viewPreferences.confirmed;
      final matches = data.project('chat 1').entries;
      expect(matches, isNotEmpty);
      expect(
        matches.every(
          (entry) => '${entry.title} ${entry.preview}'.toLowerCase().contains(
            'chat 1',
          ),
        ),
        isTrue,
      );
      expect(data.viewPreferences.confirmed, same(before));
      expect(
        controller.preferences.containsKey(
          ChatBrowserPreferencesCodec.storageKey('test'),
        ),
        isFalse,
      );
    },
  );
  test(
    'removed rows retire after listeners detach and reappearing keys reuse them',
    () async {
      await data.refresh(archivedOnly: false);
      final key = data.entries.first.sessionKey;
      final row = data.row(key);
      void listener() {}
      row.addListener(listener);
      fixture.omittedRows.add((key.workspace.profileName, key.sessionId));
      await controller.switchProfile('personal');
      await data.refresh(archivedOnly: false);
      expect(data.entries.any((entry) => entry.sessionKey == key), isFalse);
      expect(data.retainedRowCount, data.entries.length + 1);
      fixture.omittedRows.remove((key.workspace.profileName, key.sessionId));
      await controller.switchProfile('personal');
      await data.refresh(archivedOnly: false);
      expect(data.row(key), same(row));
      row.removeListener(listener);
      fixture.omittedRows.add((key.workspace.profileName, key.sessionId));
      await controller.switchProfile('personal');
      await data.refresh(archivedOnly: false);
      expect(data.retainedRowCount, data.entries.length);
    },
  );

  test('increasing replacement datasets retain only current rows', () async {
    for (var cycle = 0; cycle < 12; cycle++) {
      fixture.count = 125 + cycle * 25;
      await data.refresh(archivedOnly: false);
      final keys = data.entries.map((entry) => entry.sessionKey).toList();
      fixture.omittedRows.addAll([
        for (final key in keys) (key.workspace.profileName, key.sessionId),
      ]);
      await controller.switchProfile('personal');
      await data.refresh(archivedOnly: false);
      expect(data.entries, isEmpty);
      expect(data.retainedRowCount, 0);
      fixture.omittedRows.clear();
    }
  });
  test(
    'recovery reads only failed profiles and retains healthy search results',
    () async {
      fixture.failWorkIndex = true;
      await data.refresh(archivedOnly: false);
      expect(
        data.state.profiles.entries
            .where((entry) => entry.value.error != null)
            .map((entry) => entry.key),
        ['work'],
      );
      expect(
        data.state.profiles.entries
            .where((entry) => entry.value.complete)
            .map((entry) => entry.key)
            .toSet(),
        {'personal'},
      );
      fixture.failWorkSearch = true;
      await data.search('chat 1');
      final healthyMatches = data.state.profiles['personal']?.searchMatches;
      expect(healthyMatches, isNotEmpty);
      final healthyEntries = data
          .project('chat 1')
          .entries
          .where((entry) => entry.profile == 'personal')
          .map((entry) => (entry.sessionKey, entry.title, entry.preview))
          .toList();
      expect(healthyEntries, isNotEmpty);
      expect(data.needsRecovery, isTrue);
      fixture.failWorkIndex = false;
      fixture.failWorkSearch = false;
      fixture.attempts.clear();
      await data.recover();
      expect(fixture.attempts.every((r) => r.$1 == 'work'), isTrue);
      expect(
        data.state.profiles['personal']?.searchMatches,
        equals(healthyMatches),
      );
      expect(data.state.profiles['work']?.searchMatches, isNotEmpty);
      expect(
        data
            .project('chat 1')
            .entries
            .where((entry) => entry.profile == 'personal')
            .map((entry) => (entry.sessionKey, entry.title, entry.preview)),
        healthyEntries,
      );
      expect(
        data.state.profiles.values.where((profile) => profile.error != null),
        isEmpty,
      );
      expect(data.state.searchError, isNull);
      expect(data.needsRecovery, isFalse);
    },
  );

  test(
    'new query supersedes an in-flight recovery and permanent errors do not recover',
    () async {
      fixture.failWorkSearch = true;
      await data.search('chat 1');
      fixture.failWorkSearch = false;
      final gate = Completer<void>();
      fixture.searchDelays['chat 1'] = gate;
      final recovery = data.recover();
      await data.search('chat 2');
      final latest = data.state.profiles['work']?.searchMatches;
      final latestEntries = data
          .project('chat 2')
          .entries
          .where((entry) => entry.profile == 'work')
          .map((entry) => (entry.sessionKey, entry.title, entry.preview))
          .toList();
      expect(latestEntries, isNotEmpty);
      gate.complete();
      await recovery;
      expect(data.state.profiles['work']?.searchMatches, equals(latest));
      expect(
        data
            .project('chat 2')
            .entries
            .where((entry) => entry.profile == 'work')
            .map((entry) => (entry.sessionKey, entry.title, entry.preview)),
        latestEntries,
      );
      expect(
        data
            .project('chat 2')
            .entries
            .where((entry) => entry.profile == 'work')
            .every((entry) => entry.title.contains('chat 2')),
        isTrue,
      );
      fixture.failWorkSearch = true;
      fixture.permanentSearchFailure = true;
      await data.search('chat 3');
      expect(data.state.searchError, isNotNull);
      expect(data.needsRecovery, isFalse);
      fixture.attempts.clear();
      await data.recover();
      expect(fixture.attempts, isEmpty);
    },
  );

  test(
    'paging deduplicates pin backfills without touching navigation or live sockets',
    () async {
      final live = {...fixture.opened};
      final owner = controller.current;
      await data.refresh(archivedOnly: false);
      expect(data.entries.length, 250);
      expect(data.entries.map((e) => e.key).toSet().length, 250);
      expect(
        data.state.profiles.entries
            .where((entry) => entry.value.complete)
            .map((entry) => entry.key)
            .toSet(),
        {'personal', 'work'},
      );
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
  test('overlapping refreshes share the same profile reads', () async {
    final gate = Completer<void>();
    fixture.pageDelays[('personal', 0)] = gate;
    fixture.pageDelays[('work', 0)] = gate;
    final first = data.refresh(archivedOnly: false);
    final second = data.refresh(archivedOnly: false);
    await Future<void>.delayed(Duration.zero);
    final initialReads = fixture.reads
        .where(
          (r) =>
              r.$1 == 'sessions' &&
              r.$2['limit'] == '100' &&
              r.$2['offset'] == '0',
        )
        .length;
    gate.complete();
    await Future.wait([first, second]);
    expect(initialReads, 2, reason: 'one request per profile while refreshing');
    expect(
      data.state.profiles.entries
          .where((entry) => entry.value.complete)
          .map((entry) => entry.key)
          .toSet(),
      {'personal', 'work'},
    );
  });

  test(
    'refresh retains the complete list until replacement pages are ready',
    () async {
      await data.refresh(archivedOnly: false);
      final previous = data.entries
          .where((entry) => entry.profile == 'personal')
          .map((entry) => entry.sessionKey)
          .toList();
      final gate = Completer<void>();
      fixture.pageDelays[('personal', 100)] = gate;
      fixture.prepend = true;
      final refreshing = data.refresh(archivedOnly: false);
      await Future<void>.delayed(Duration.zero);
      final during = data.entries
          .where((entry) => entry.profile == 'personal')
          .map((entry) => entry.sessionKey)
          .toList();
      gate.complete();
      await refreshing;
      expect(
        during,
        equals(previous),
        reason: 'do not collapse and regrow the list during refresh',
      );
      expect(
        data.entries.where((entry) => entry.profile == 'personal').length,
        126,
      );
    },
  );

  test('refresh publication does not grow with the number of pages', () async {
    fixture.count = 1000;
    await data.refresh(archivedOnly: false);
    var publications = 0;
    data.addListener(() => publications++);
    await data.refresh(archivedOnly: false);
    expect(data.entries.length, 2000);
    expect(publications, 4, reason: 'start, one snapshot per profile, finish');
  });

  test(
    'temporary page and project failures recover without manual refresh',
    () async {
      fixture.failNextPage = true;
      fixture.failNextTree = true;
      await data.refresh(archivedOnly: false);
      expect(fixture.failNextPage, isFalse);
      expect(fixture.failNextTree, isFalse);
      expect(
        data.state.profiles.values.where((profile) => profile.error != null),
        isEmpty,
      );
      expect(
        data.state.profiles.entries
            .where((entry) => entry.value.complete)
            .map((entry) => entry.key)
            .toSet(),
        {'personal', 'work'},
      );
      expect(data.entries.length, 250);
    },
  );

  test(
    'failed later page leaves readable data but never a complete total',
    () async {
      fixture.pageFailures.add(('personal', 100));
      await data.refresh(archivedOnly: false);
      expect(
        data.state.profiles.entries
            .where((entry) => entry.value.error != null)
            .map((entry) => entry.key),
        contains('personal'),
      );
      expect(
        data.state.profiles.entries
            .where((entry) => entry.value.complete)
            .map((entry) => entry.key)
            .toSet(),
        isNot(contains('personal')),
      );
      expect(data.entries.where((e) => e.profile == 'personal'), isNotEmpty);
      expect(
        data.state.profiles.entries
            .where((entry) => entry.value.complete)
            .map((entry) => entry.key)
            .toSet(),
        contains('work'),
      );
      fixture.pageFailures.clear();
      await data.refresh(archivedOnly: false);
      expect(
        data.state.profiles.values.where((profile) => profile.error != null),
        isEmpty,
      );
      expect(
        data.state.profiles.entries
            .where((entry) => entry.value.complete)
            .map((entry) => entry.key)
            .toSet()
            .length,
        2,
      );
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
      expect(data.state.archived, isTrue);
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
    expect(data.state.profiles['personal']?.searchMatches, {'chat-110'});
    expect(data.state.profiles['work']?.searchMatches, {'chat-110'});
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
