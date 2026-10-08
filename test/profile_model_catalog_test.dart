import 'package:wing/core/services/administration_repository.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/model_catalog.dart';
import 'package:wing/core/models/model_catalog_details.dart';
import 'package:wing/core/services/profile_model_catalog.dart';

Map<String, dynamic> payload(String model) => {
  'providers': [
    {
      'slug': 'openai-codex',
      'name': 'OpenAI subscription',
      'models': [model],
    },
  ],
};

void main() {
  final scope = WorkspaceScope(
    connectionId: 'one',
    connectionIdentity: 'identity',
    profileName: 'work',
  );
  test(
    'administration consumers share only their captured profile owner and cannot reopen it after close',
    () async {
      final queries = <Map<String, String>>[];
      final repository = AdministrationRepository(
        connectionId: 'one',
        connectionIdentity: 'identity',
        connectionLabel: 'Test',
        request: (method, endpoint, query, body) async {
          expect(endpoint, 'model/options');
          queries.add(Map.of(query));
          return payload('gpt-6-astra');
        },
        settingsWrite: (_, _, _, _) async =>
            throw StateError('Unexpected write'),
        ownedMutation: (_, _, _, _, _, _) async =>
            throw StateError('Unexpected mutation'),
        gateway: (_) => throw StateError('No socket needed'),
      );
      final work = repository.profile('work').modelCatalog;
      expect(identical(work, repository.profile('work').modelCatalog), isTrue);
      expect(
        identical(work, repository.profile('personal').modelCatalog),
        isFalse,
      );
      await work.load(explicitOnly: true, refresh: true);
      expect(queries.single, {
        'profile': 'work',
        'explicit_only': '1',
        'refresh': '1',
      });
      repository.close();
      await expectLater(work.load(), throwsStateError);
      expect(() => repository.profile('work').modelCatalog, throwsStateError);
      expect(queries, hasLength(1));
    },
  );
  test(
    'concurrent consumers share reads; refresh supersedes held results',
    () async {
      final requests = <Completer<Map<String, dynamic>>>[];
      final refreshes = <bool>[];
      final owner = ProfileModelCatalog(
        scope: scope,
        read: ({required refresh, required explicitOnly}) {
          refreshes.add(refresh);
          final request = Completer<Map<String, dynamic>>();
          requests.add(request);
          return request.future;
        },
      );
      final first = owner.load();
      expect(identical(first, owner.load()), isTrue);
      final old = expectLater(first, throwsStateError);
      final refreshed = owner.load(refresh: true);
      requests[1].complete(payload('gpt-6-astra'));
      await refreshed;
      requests[0].complete(payload('gpt-5.6-sol'));
      await old;
      expect(owner.snapshot!.choices.single.model, 'gpt-6-astra');
      expect(refreshes, [false, true]);
      expect(owner.scope, scope);
      owner.close();
    },
  );
  test(
    'explicit and chat policies never share pending reads or snapshots',
    () async {
      final held = <bool, Completer<Map<String, dynamic>>>{};
      final owner = ProfileModelCatalog(
        scope: scope,
        read: ({required refresh, required explicitOnly}) =>
            (held[explicitOnly] = Completer<Map<String, dynamic>>()).future,
      );
      final chat = owner.load();
      final explicit = owner.load(explicitOnly: true);
      held[true]!.complete(payload('gpt-5.6-sol'));
      expect((await explicit).choices.single.model, 'gpt-5.6-sol');
      expect(owner.snapshot, isNull);
      held[false]!.complete(payload('gpt-6-astra'));
      await chat;
      expect(owner.snapshot!.choices.single.model, 'gpt-6-astra');
      owner.close();
    },
  );
  test(
    'a synchronous transport failure does not poison the next load',
    () async {
      var calls = 0;
      final owner = ProfileModelCatalog(
        scope: scope,
        read: ({required refresh, required explicitOnly}) {
          if (++calls == 1) throw StateError('Closed request');
          return Future.value(payload('gpt-6-astra'));
        },
      );
      await expectLater(owner.load(), throwsStateError);
      expect((await owner.load()).choices.single.model, 'gpt-6-astra');
      expect(calls, 2);
      owner.close();
    },
  );
  test(
    'failed reads retain last snapshot; close fences pending completion',
    () async {
      var fail = false;
      final held = Completer<Map<String, dynamic>>();
      var hold = false;
      final owner = ProfileModelCatalog(
        scope: scope,
        read: ({required refresh, required explicitOnly}) async {
          if (hold) return held.future;
          if (fail) throw StateError('offline');
          return payload('gpt-6-astra');
        },
      );
      await owner.load();
      fail = true;
      await expectLater(owner.load(), throwsStateError);
      expect(owner.snapshot!.choices.single.model, 'gpt-6-astra');
      hold = true;
      final pending = expectLater(owner.load(), throwsStateError);
      owner.close();
      held.complete(payload('gpt-5.6-sol'));
      await pending;
      expect(owner.snapshot, isNull);
      await expectLater(owner.load(), throwsStateError);
    },
  );
  test(
    'pool quotas remain per account; optional and malformed fields stay absent',
    () {
      final catalog = ModelCatalog.fromOptions({
        'providers': [
          {
            'slug': 'openai-codex',
            'name': 'Subscription',
            'models': ['gpt-6-astra'],
            'usage': {
              'accounts': [
                {
                  'id': 'a',
                  'label': 'Personal',
                  'state': 'ready',
                  'windows': [
                    {
                      'label': '5h',
                      'used_percent': 12.5,
                      'scope': 'account',
                      'resets_at': '2026-10-07T15:00:00Z',
                    },
                  ],
                },
                {
                  'id': 'b',
                  'label': 'Work',
                  'state': 'limited',
                  'windows': [
                    {'label': 'Week', 'used_percent': 100, 'scope': 'account'},
                  ],
                  'resets_at': '2026-10-08T15:00:00Z',
                },
                {'id': 'c', 'label': '', 'state': 'unavailable', 'windows': []},
              ],
            },
            'pricing': {
              'gpt-6-astra': {'input': r'$5.00', 'output': null, 'free': false},
            },
          },
        ],
      });
      final usage = catalog.provider('openai-codex')!.usage!;
      expect(usage.windows, isEmpty);
      expect(usage.accounts, hasLength(3));
      expect(usage.accounts.first.windows.single.usedPercent, 12.5);
      expect(usage.accounts[1].state, AccountUsageState.limited);
      expect(usage.accounts[1].resetsAt, DateTime.utc(2026, 10, 8, 15));
      expect(usage.accounts.last.windows, isEmpty);
      expect(catalog.choices.single.controls, isNull);
      expect(catalog.choices.single.prices!.output, isNull);
      expect(() => usage.accounts.clear(), throwsUnsupportedError);
    },
  );
}
