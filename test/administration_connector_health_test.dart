import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/administration_health.dart';
import 'package:wing/core/services/administration_overview.dart';

import 'support/administration_fixture.dart';

void main() {
  late AdministrationFixture fixture;
  late AdministrationOverview overview;
  late AdministrationHealth health;
  var servers = <Map<String, dynamic>>[];
  late Future<Map<String, dynamic>> Function(String) probe;

  setUp(() {
    fixture = AdministrationFixture();
    servers = [];
    probe = (_) async => {'ok': true};
    fixture.override = (method, path, query, body) async {
      expect(query['profile'], 'work');
      if (method == 'GET' && path == 'mcp/servers') {
        return {'servers': servers};
      }
      expect(method, 'POST');
      return probe(path);
    };
    overview = AdministrationOverview(fixture.server.profile('work'));
    health = AdministrationHealth(fixture.server)..selectProfile(overview);
  });
  tearDown(() {
    health.dispose();
    overview.dispose();
    fixture.server.close();
  });
  Future<void> refresh() =>
      overview.refresh(keys: {'connectors'}, testConnectors: true);
  AdministrationHealthFinding finding() => health.profileFindings.singleWhere(
    (f) => f.title == 'Connector settings',
  );

  test('empty and disabled connector lists need no probes', () async {
    await refresh();
    expect(finding().detail, 'No connectors configured');
    servers = [
      {'name': 'disabled', 'enabled': false},
    ];
    await refresh();
    expect(finding().detail, 'No connectors enabled');
    expect(fixture.requests.every((r) => r.$1 == 'GET'), isTrue);
  });

  test('only enabled connectors are tested in the captured profile', () async {
    servers = [
      {'name': 'service / one', 'enabled': true},
      {'name': 'disabled', 'enabled': false},
    ];
    await refresh();
    expect(fixture.requests.map((r) => r.$2), [
      'mcp/servers',
      'mcp/servers/service%20%2F%20one/test',
    ]);
    expect(finding().detail, '1 of 1 connection check passed');
    expect(finding().status, AdministrationHealthStatus.healthy);
  });

  test('failed and unavailable probes are distinct and can recover', () async {
    servers = [
      {'name': 'first', 'enabled': true},
      {'name': 'second', 'enabled': true},
    ];
    probe = (path) async =>
        path.contains('/first/') ? {'ok': false} : throw StateError('Offline');
    await refresh();
    expect(finding().detail, '0 passed · 1 failed · 1 couldn’t be checked');
    expect(finding().status, AdministrationHealthStatus.warning);
    expect(overview.connectorChecks, {'first': false, 'second': null});
    probe = (_) async => {'ok': 'invalid'};
    await refresh();
    expect(finding().status, AdministrationHealthStatus.unknown);
    expect(finding().detail, '0 passed · 2 couldn’t be checked');
    probe = (_) async => {'ok': true};
    await refresh();
    expect(finding().detail, '2 of 2 connection checks passed');
  });

  test('late connector checks cannot overwrite a newer refresh', () async {
    servers = [
      {'name': 'first', 'enabled': true},
    ];
    final pending = Completer<Map<String, dynamic>>();
    final started = Completer<void>();
    probe = (_) {
      started.complete();
      return pending.future;
    };
    final old = refresh();
    await started.future;
    probe = (_) async => {'ok': true};
    await refresh();
    pending.complete({'ok': false});
    await old;
    expect(finding().detail, '1 of 1 connection check passed');
  });
}
