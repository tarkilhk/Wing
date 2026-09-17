import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/administration_overview.dart';
import 'support/administration_fixture.dart';

void main() {
  test(
    'independent reads retain good observations after a failed refresh',
    () async {
      final fixture = AdministrationFixture();
      var fail = false;
      fixture.override = (method, path, query, body) async {
        if (path == 'config') {
          if (fail) throw StateError('offline');
          return {
            'memory': {'memory_enabled': true},
          };
        }
        if (path == 'model/info') throw StateError('unavailable');
        if (path == 'providers/oauth') return {'providers': []};
        if (path == 'mcp/servers') return {'servers': []};
        return {'data': []};
      };
      final overview = AdministrationOverview(
        fixture.server.profile('personal'),
      );
      addTearDown(overview.dispose);
      await overview.refresh();
      final checked = overview.observations['config']!.checkedAt;
      expect(overview.observations['config']!.data, {
        'memory': {'memory_enabled': true},
      });
      expect(overview.observations['model']!.error, isNotNull);
      expect(overview.observations['skills']!.data, {'data': []});
      fail = true;
      await overview.refresh();
      expect(overview.observations['config']!.checkedAt, checked);
      expect(overview.observations['config']!.data, isNotNull);
      expect(overview.observations['config']!.error, isNotNull);
      expect(
        fixture.requests.every(
          (r) => r.$1 == 'GET' && r.$3['profile'] == 'personal',
        ),
        isTrue,
      );
    },
  );

  test(
    'targeted refresh does not reread unrelated profile observations',
    () async {
      final fixture = AdministrationFixture();
      final overview = AdministrationOverview(
        fixture.server.profile('personal'),
      );
      addTearDown(overview.dispose);
      await overview.refresh();
      final model = overview.observations['model']!.checkedAt;
      fixture.requests.clear();
      await overview.refresh(keys: {'config'});
      expect(fixture.requests.map((r) => r.$2), ['config']);
      expect(overview.observations['model']!.checkedAt, model);
    },
  );

  test(
    'older refresh and disposed observers cannot publish late results',
    () async {
      final fixture = AdministrationFixture();
      final pending = Completer<Map<String, dynamic>>();
      var reads = 0;
      fixture.override = (_, path, _, _) async {
        if (path == 'config') {
          if (++reads == 1) return pending.future;
          return {'version': 2};
        }
        if (path == 'providers/oauth') return {'providers': []};
        if (path == 'mcp/servers') return {'servers': []};
        return {'data': []};
      };
      final overview = AdministrationOverview(fixture.server.profile('work'));
      final old = overview.refresh();
      await overview.refresh();
      expect(overview.observations['config']!.data, {'version': 2});
      overview.dispose();
      pending.complete({'version': 1});
      await old;
      expect(overview.observations['config']!.data, {'version': 2});
    },
  );

  test('malformed collection does not erase last confirmed data', () async {
    final fixture = AdministrationFixture();
    var malformed = false;
    fixture.override = (_, path, _, _) async => switch (path) {
      'skills' => {
        'data': malformed
            ? 'invalid'
            : [
                {'name': 'research', 'enabled': true},
              ],
      },
      'providers/oauth' => {'providers': []},
      'mcp/servers' => {'servers': []},
      _ => {'data': []},
    };
    final overview = AdministrationOverview(fixture.server.profile('work'));
    addTearDown(overview.dispose);
    await overview.refresh();
    malformed = true;
    await overview.refresh();
    expect(overview.observations['skills']!.data!['data'], isList);
    expect(overview.observations['skills']!.error, isNotNull);
  });
}
