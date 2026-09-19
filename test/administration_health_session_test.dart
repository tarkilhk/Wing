import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/administration/admin_runtime_health.dart';
import 'package:wing/core/services/administration_health.dart';
import 'package:wing/core/services/administration_health_session.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profiles_repository.dart';

void main() {
  late SharedPreferences preferences;
  late AdministrationRepository server;
  late DateTime now;
  late List<(String, String, String?)> requests;
  late Map<String, ProfileWorkspaceData> workspaces;
  Completer<Map<String, dynamic>>? accessGate;
  var diagnosticRunning = false;
  var tasksOffline = false;
  var nextPid = 8;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    now = DateTime(2026, 9, 19, 12);
    requests = [];
    workspaces = {};
    accessGate = null;
    diagnosticRunning = false;
    tasksOffline = false;
    nextPid = 8;
    ProfileGateway gateway(String name) => ProfileGateway(
      scope: WorkspaceScope(
        connectionId: 'server',
        connectionIdentity: 'endpoint',
        profileName: name,
      ),
      get: (_, _) async => {},
      discover: () async => const ProfileDiscovery(
        currentName: 'default',
        activeName: 'default',
        profiles: [
          HermesProfile(name: 'default', isDefault: true),
          HermesProfile(name: 'work'),
        ],
      ),
      rpc: (method, params) async {
        requests.add(('RPC', method, name));
        if (method == 'setup.runtime_check' &&
            name == 'default' &&
            accessGate != null) {
          return accessGate!.future;
        }
        return {
          'profile': name,
          'ok': true,
          'provider_configured': true,
          'model': 'model-$name',
          'provider': 'provider',
        };
      },
    );
    server = AdministrationRepository(
      connectionId: 'server',
      connectionIdentity: 'endpoint',
      connectionLabel: 'Server',
      gateway: gateway,
      request: (method, path, query, body) async {
        final name = query['profile'];
        requests.add((method, path, name));
        return switch (path) {
          'model/info' => {
            'model': 'model-$name',
            'provider': 'provider',
            'api_key': 'must-not-save',
          },
          'providers/oauth' => {'providers': []},
          'tools/toolsets' => {
            'data': [
              {
                'name': 'tool-$name',
                'enabled': true,
                'configured': name == 'default',
              },
            ],
          },
          'mcp/servers' => {'servers': []},
          'cron/jobs' =>
            tasksOffline ? throw StateError('offline') : {'data': []},
          'ops/doctor' ||
          'ops/security-audit' => {'name': path.substring(4), 'pid': ++nextPid},
          'actions/doctor/status' || 'actions/security-audit/status' => {
            'pid': nextPid,
            'running': diagnosticRunning,
            'exit_code': diagnosticRunning ? null : 0,
            'lines': ['Stored diagnostic output'],
          },
          _ => throw StateError('Unexpected $method $path'),
        };
      },
    );
    for (final name in ['default', 'work']) {
      workspaces[name] = ProfileWorkspaceData(gateway(name));
    }
  });
  tearDown(() {
    server.close();
  });

  AdministrationHealthSession create() =>
      AdministrationHealthSession(server, preferences, now: () => now);
  Future<void> select(AdministrationHealthSession session, String name) async {
    session.select(workspaces[name]);
    await session.refresh(workspaces[name]!);
    await session.saved;
  }

  void completed(
    AdministrationHealthSession session,
    String path,
    DateTime at,
  ) {
    final generation = session.health.beginDiagnostic(path)!;
    session.health.observeDiagnostic(
      path,
      AdminDiagnosticObservation(
        AdministrationAction(path.substring(4), nextPid),
        {
          'pid': nextPid,
          'running': false,
          'exit_code': 0,
          'lines': ['Stored diagnostic output'],
        },
        at,
      ),
      generation: generation,
    );
    session.health.finishDiagnostic(path, generation);
  }

  testWidgets(
    'profile results survive restart, stay separate, and expire independently',
    (tester) async {
      var session = create();
      await select(session, 'default');
      now = now.add(const Duration(hours: 2));
      await select(session, 'work');
      expect(
        session.health.profileFindings.any(
          (f) => f.detail == 'tool-work needs setup',
        ),
        isTrue,
      );
      session.dispose();
      await session.saved;
      final stored = preferences
          .getKeys()
          .where((k) => k.startsWith('health-results:'))
          .single;
      expect(preferences.getString(stored), isNot(contains('must-not-save')));
      // Recreate preferences too, exercising the serialized state rather than a registry.
      SharedPreferences.setMockInitialValues({
        stored: preferences.getString(stored)!,
      });
      preferences = await SharedPreferences.getInstance();
      requests.clear();
      session = create();
      session.select(workspaces['default']);
      await tester.pump();
      expect(requests, isEmpty);
      expect(
        session.health.profileFindings.any(
          (f) => f.detail == 'No setup gaps reported for enabled tools',
        ),
        isTrue,
      );
      expect(
        session
            .checksFor(workspaces['default']!)
            .healthObservation
            .finding
            ?.detail,
        'Credentials available',
      );
      session.select(workspaces['work']);
      await tester.pump();
      expect(requests, isEmpty);
      expect(
        session.health.profileFindings.any(
          (f) => f.detail == 'tool-work needs setup',
        ),
        isTrue,
      );
      now = now.add(const Duration(hours: 22));
      session.select(workspaces['work']);
      await tester.pump();
      expect(requests, isEmpty);
      session.select(workspaces['default']);
      await tester.pumpAndSettle();
      expect(
        requests.where((r) => r.$2 == 'setup.runtime_check').map((r) => r.$3),
        ['default'],
      );
      session.dispose();
    },
  );

  testWidgets('checks finish off-screen and are reused on returning', (
    tester,
  ) async {
    final session = create();
    accessGate = Completer();
    session.select(workspaces['default']);
    await tester.pump();
    expect(session.checking('default'), isTrue);
    session.select(workspaces['work']);
    await tester.pumpAndSettle();
    accessGate!.complete({
      'ok': true,
      'profile': 'default',
      'model': 'model-default',
      'provider': 'provider',
    });
    await tester.pumpAndSettle();
    requests.clear();
    session.select(workspaces['default']);
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(session.checking('default'), isFalse);
    expect(
      session
          .checksFor(workspaces['default']!)
          .healthObservation
          .finding
          ?.detail,
      'Credentials available',
    );
    session.dispose();
  });

  testWidgets(
    'server results survive restart and only expired diagnostics rerun on entry',
    (tester) async {
      var session = create();
      completed(session, 'ops/doctor', now.subtract(const Duration(hours: 25)));
      completed(
        session,
        'ops/security-audit',
        now.subtract(const Duration(hours: 2)),
      );
      session.dispose();
      await session.saved;
      session = create();
      expect(session.health.diagnostics, hasLength(2));
      expect(session.health.diagnostics['ops/doctor']!.status['lines'], [
        'Stored diagnostic output',
      ]);
      expect(requests, isEmpty);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminRuntimeHealth(health: session.health)),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.$1 == 'POST').map((r) => r.$2), [
        'ops/doctor',
      ]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminRuntimeHealth(health: session.health)),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.$1 == 'POST'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'unfinished diagnostics resume reads after restart without starting again',
    (tester) async {
      var session = create();
      final generation = session.health.beginDiagnostic('ops/doctor')!;
      session.health.observeDiagnostic(
        'ops/doctor',
        AdminDiagnosticObservation(AdministrationAction('doctor', nextPid), {
          'running': true,
        }, now),
        generation: generation,
      );
      session.health.finishDiagnostic('ops/doctor', generation);
      session.dispose();
      await session.saved;
      session = create();
      await tester.pump(Duration.zero);
      expect(requests, [('GET', 'actions/doctor/status', null)]);
      expect(session.health.diagnostics['ops/doctor']!.outcome, 'Completed');
      session.dispose();
    },
  );

  testWidgets('failed task refresh keeps the saved observation after restart', (
    tester,
  ) async {
    var session = create();
    await select(session, 'default');
    final original = session.health.profileFindings.singleWhere(
      (f) => f.title == 'Scheduled tasks',
    );
    session.dispose();
    await session.saved;
    now = now.add(const Duration(hours: 25));
    tasksOffline = true;
    session = create();
    session.select(workspaces['default']);
    await tester.pumpAndSettle();
    final retained = session.health.profileFindings.singleWhere(
      (f) => f.title == 'Scheduled tasks',
    );
    expect(retained.checkedAt, original.checkedAt);
    expect(retained.detail, contains(original.detail));
    expect(retained.detail, contains('Refresh unavailable'));
    session.dispose();
  });

  testWidgets(
    'changed connection identity does not restore another servers results',
    (tester) async {
      final session = create();
      completed(session, 'ops/doctor', now);
      await select(session, 'default');
      session.dispose();
      await session.saved;
      final other = AdministrationRepository(
        connectionId: 'server',
        connectionIdentity: 'different-endpoint',
        connectionLabel: 'Server',
        request: server.request,
        gateway: server.gateway,
      );
      final fresh = AdministrationHealthSession(other, preferences);
      expect(fresh.health.diagnostics, isEmpty);
      expect(fresh.overviews, isEmpty);
      fresh.dispose();
      other.close();
    },
  );

  test('snapshot is valid JSON with distinct profile timestamps', () async {
    final session = create();
    await select(session, 'default');
    now = now.add(const Duration(hours: 1));
    await select(session, 'work');
    final key = preferences
        .getKeys()
        .where((k) => k.startsWith('health-results:'))
        .single;
    final json = jsonDecode(preferences.getString(key)!) as Map;
    expect(
      json['profiles']['default']['refreshedAt'],
      isNot(json['profiles']['work']['refreshedAt']),
    );
    session.dispose();
  });
}
