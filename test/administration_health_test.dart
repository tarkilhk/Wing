import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/administration_health.dart';
import 'package:wing/core/services/administration_overview.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/server_connection_status.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/profile_diagnostics_panel.dart';

void main() {
  final observedAt = DateTime.utc(2026, 9, 17, 12);
  late DateTime now;
  late AdministrationRepository server;
  late AdministrationHealth health;
  late Future<Map<String, dynamic>> Function(String) readiness;
  late List<String> calls;

  setUp(() {
    now = observedAt;
    calls = [];
    readiness = (profile) async => {
      'profile': profile,
      'provider_configured': true,
    };
    server = AdministrationRepository(
      connectionId: 'server',
      connectionIdentity: 'endpoint',
      connectionLabel: 'Server',
      request: (method, path, query, body) async {
        calls.add('$method $path');
        return switch (path) {
          'profiles/active' => {'current': 'default'},
          'profiles' => {
            'profiles': [
              {'name': 'default', 'is_default': true},
            ],
          },
          _ => throw StateError('Unexpected request'),
        };
      },
      gateway: (name) => ProfileGateway(
        scope: WorkspaceScope(
          connectionId: 'server',
          connectionIdentity: 'endpoint',
          profileName: name,
        ),
        get: (path, query) async => throw StateError('Unexpected GET'),
        discover: () => server.discover(),
        rpc: (method, params) {
          calls.add('$method ${params['profile']}');
          expect(method, 'setup.status');
          return readiness(name);
        },
      ),
    );
    health = AdministrationHealth(server, now: () => now);
  });

  tearDown(() {
    health.dispose();
    server.close();
  });

  AdministrationOverview overview(String name) {
    final value = AdministrationOverview(server.profile(name));
    final data = {
      'model': {'provider': 'example', 'model': 'research'},
      'access': {'providers': <Map<String, dynamic>>[]},
      'tools': {'data': <Map<String, dynamic>>[]},
      'connectors': {'servers': <Map<String, dynamic>>[]},
    };
    for (final entry in data.entries) {
      value.observations[entry.key] = AdministrationObservation()
        ..data = entry.value
        ..checkedAt = now;
    }
    addTearDown(value.dispose);
    return value;
  }

  test(
    'entry consumes existing observations and never runs diagnostics',
    () async {
      health.selectProfile(overview('default'));
      expect(calls, isEmpty);
      expect(health.status, AdministrationHealthStatus.unknown);
      await health.refreshReadiness();
      expect(calls, ['setup.status default']);
      expect(health.status, AdministrationHealthStatus.healthy);
      expect(health.diagnosticCoverage, 'Doctor and security audit not run');
      expect(health.statusLabel, 'No issues in available observations');
    },
  );

  test(
    'missing and malformed observations are unknown; refresh retains prior results',
    () async {
      final source = overview('default');
      health.selectProfile(source);
      await health.refreshReadiness();
      final model = source.observations['model']!;
      model.data = {};
      expect(health.status, AdministrationHealthStatus.unknown);
      model.data = {'provider': 'example', 'model': 'research'};
      model.loading = true;
      expect(health.status, AdministrationHealthStatus.healthy);
      model.loading = false;
      model.error = 'Offline';
      expect(health.status, AdministrationHealthStatus.unknown);
      model.error = null;
      source.observations['tools']!.data = {
        'data': [<String, dynamic>{}],
      };
      expect(health.status, AdministrationHealthStatus.unknown);
      source.observations['tools']!.data = {'data': []};
      source.observations['access']!.data = {
        'providers': [
          {'status': {}},
        ],
      };
      expect(health.status, AdministrationHealthStatus.unknown);
    },
  );

  test(
    'configuration does not establish runtime health or provider access',
    () async {
      health.selectProfile(overview('default'));
      await health.refreshRuntimeIdentity();
      expect(health.runtimeIdentity?['name'], 'default');
      expect(health.status, AdministrationHealthStatus.unknown);
      readiness = (profile) async => {'profile': profile};
      await health.refreshReadiness();
      expect(health.status, AdministrationHealthStatus.unknown);
      readiness = (profile) async => {
        'profile': 'another',
        'provider_configured': true,
      };
      await health.refreshReadiness();
      expect(health.status, AdministrationHealthStatus.unknown);
      readiness = (profile) async => {
        'profile': profile,
        'provider_configured': false,
      };
      await health.refreshReadiness();
      expect(health.status, AdministrationHealthStatus.warning);
    },
  );

  test(
    'expired sign-in outranks setup warnings and survives failed refresh',
    () async {
      final source = overview('default');
      health.selectProfile(source);
      await health.refreshReadiness();
      source.observations['tools']!.data = {
        'data': [
          {'enabled': true, 'configured': false},
        ],
      };
      expect(health.status, AdministrationHealthStatus.warning);
      source.observations['access']!.data = {
        'providers': [
          {
            'status': {
              'logged_in': true,
              'expires_at': observedAt
                  .subtract(const Duration(seconds: 1))
                  .toIso8601String(),
            },
          },
        ],
      };
      expect(health.status, AdministrationHealthStatus.failure);
      source.observations['access']!.error = 'Offline';
      now = observedAt.add(const Duration(minutes: 6));
      expect(health.status, AdministrationHealthStatus.failure);
      expect(
        health.profileFindings
            .where((f) => f.title == 'Provider access')
            .single
            .stale,
        isTrue,
      );
    },
  );

  test(
    'age alone preserves observations; failed refresh qualifies retained results',
    () async {
      health.selectProfile(overview('default'));
      await health.refreshReadiness();
      now = observedAt.add(const Duration(minutes: 5));
      expect(health.status, AdministrationHealthStatus.healthy);
      expect(health.profileFindings.every((f) => f.stale), isTrue);
      now = observedAt;
      readiness = (_) => Future.error(StateError('Offline'));
      await health.refreshReadiness();
      expect(health.status, AdministrationHealthStatus.unknown);
      expect(
        health.profileFindings.first.detail,
        contains('Refresh unavailable'),
      );
      expect(health.profileFindings.first.checkedAt, observedAt);
    },
  );

  test(
    'late readiness cannot recolor another profile or an A-B-A selection',
    () async {
      final a = overview('default'), b = overview('work');
      final pending = Completer<Map<String, dynamic>>();
      readiness = (_) => pending.future;
      health.selectProfile(a);
      final read = health.refreshReadiness();
      health.selectProfile(null);
      health.selectProfile(b);
      health.selectProfile(a);
      pending.complete({'profile': 'default', 'provider_configured': true});
      await read;
      expect(health.status, AdministrationHealthStatus.unknown);
      expect(health.profileFindings.first.checkedAt, isNull);
    },
  );

  test(
    'retained runtime results remain scoped to connection across selection',
    () async {
      const path = 'ops/doctor';
      health.selectProfile(overview('default'));
      await health.refreshReadiness();
      final generation = health.beginDiagnostic(path)!;
      health.observeDiagnostic(
        path,
        AdminDiagnosticObservation(const AdministrationAction('doctor', 7), {
          'running': false,
          'exit_code': 1,
          'lines': ['Finding'],
        }, now),
        generation: generation,
      );
      health.finishDiagnostic(path, generation);
      health.selectProfile(overview('work'));
      expect(health.status, AdministrationHealthStatus.failure);
      expect(health.diagnostics[path]!.action.pid, 7);
      final rerun = health.beginDiagnostic(path)!;
      health.observeDiagnostic(
        path,
        AdminDiagnosticObservation(const AdministrationAction('doctor', 8), {
          'running': false,
          'exit_code': 0,
          'lines': ['Warnings remain'],
        }, now),
        generation: rerun,
      );
      health.finishDiagnostic(path, rerun);
      await health.refreshReadiness();
      expect(health.status, AdministrationHealthStatus.unknown);
      health.observeDiagnostic(
        path,
        AdminDiagnosticObservation(const AdministrationAction('doctor', 7), {
          'running': false,
          'exit_code': 1,
        }, now),
        generation: generation,
      );
      expect(health.diagnostics[path]!.action.pid, 8);
      expect(health.status, AdministrationHealthStatus.unknown);
      expect(calls.where((c) => c.startsWith('POST')), isEmpty);
    },
  );

  test('invalid diagnostic exit codes cannot report completed or failed', () {
    final invalid = AdminDiagnosticObservation(
      const AdministrationAction('doctor', 7),
      {'running': false, 'exit_code': '0'},
      now,
    );
    expect(invalid.failed, isFalse);
    expect(invalid.outcome, 'Outcome unavailable');
  });

  test(
    'explicit credential failure overrides green and remains profile scoped',
    () async {
      now = DateTime.now();
      final selected = overview('default');
      health.selectProfile(selected);
      await health.refreshReadiness();
      expect(health.status, AdministrationHealthStatus.healthy);

      final runtime = Completer<Map<String, dynamic>>();
      final checks = ProfileDiagnosticsController(
        workspace: ProfileWorkspaceData(
          ProfileGateway(
            scope: selected.profile.scope,
            get: (path, query) async {
              expect(path, 'sessions');
              return {};
            },
            rpc: (method, params) async {
              expect(params['profile'], 'default');
              return switch (method) {
                'setup.status' => {
                  'profile': 'default',
                  'provider_configured': true,
                },
                'setup.runtime_check' => await runtime.future,
                _ => throw StateError('Unexpected diagnostic'),
              };
            },
            discover: () => server.discover(),
          ),
        ),
        connectionLabel: server.connectionLabel,
      );
      addTearDown(checks.dispose);
      checks.addListener(
        () => health.updateProfileChecks(checks.healthObservation),
      );
      expect(checks.healthObservation.finding, isNull);

      final checking = checks.check();
      expect(health.status, AdministrationHealthStatus.unknown);
      runtime.complete({'profile': 'default', 'ok': false});
      await checking;
      expect(health.status, AdministrationHealthStatus.failure);
      expect(
        health.profileFindings.last.detail,
        contains('credentials are unavailable'),
      );
      await health.refreshReadiness();
      expect(health.status, AdministrationHealthStatus.failure);

      health.selectProfile(overview('work'));
      await health.refreshReadiness();
      expect(health.status, AdministrationHealthStatus.healthy);
      health.updateProfileChecks(checks.healthObservation);
      expect(health.status, AdministrationHealthStatus.healthy);

      health.selectProfile(selected);
      health.updateProfileChecks(checks.healthObservation);
      await health.refreshReadiness();
      expect(health.status, AdministrationHealthStatus.failure);
    },
  );

  test('an explicit check with unavailable outcome prevents green', () async {
    now = DateTime.now();
    health.selectProfile(overview('default'));
    await health.refreshReadiness();
    final checks = ProfileDiagnosticsController(
      workspace: ProfileWorkspaceData(
        ProfileGateway(
          scope: health.overview!.profile.scope,
          get: (path, query) async => {},
          rpc: (method, params) async => method == 'setup.status'
              ? {'profile': 'default', 'provider_configured': true}
              : {},
          discover: () => server.discover(),
        ),
      ),
      connectionLabel: server.connectionLabel,
    );
    addTearDown(checks.dispose);
    checks.addListener(
      () => health.updateProfileChecks(checks.healthObservation),
    );
    await checks.check();
    now = DateTime.now();
    expect(health.status, AdministrationHealthStatus.unknown);
    expect(health.profileFindings.last.stale, isFalse);
    expect(health.profileFindings.last.detail, 'Access checks are incomplete');
  });

  test(
    'connection interruption neutralizes otherwise current observations',
    () async {
      final connection = ServerConnectionStatus('Server')..accessAvailable();
      health.dispose();
      health = AdministrationHealth(
        server,
        now: () => now,
        connectionStatus: connection,
      );
      addTearDown(connection.dispose);
      health.selectProfile(overview('default'));
      await health.refreshReadiness();
      expect(health.status, AdministrationHealthStatus.healthy);
      connection.beginRecovery('workspace');
      expect(health.status, AdministrationHealthStatus.unknown);
      expect(health.profileFindings.first.detail, 'Reconnecting');
      connection.endRecovery('workspace');
      connection.liveChanged('workspace', false);
      expect(health.status, AdministrationHealthStatus.unknown);
      connection.liveChanged('workspace', true);
      expect(health.status, AdministrationHealthStatus.healthy);
    },
  );
}
