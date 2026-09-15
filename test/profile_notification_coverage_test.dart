import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/hermes_profile.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/profile_gateway.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/services/profiles_repository.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationCoverageHost {
  final gateways = <String, ProfileGateway>{};
  final saved = <String, List<Map<String, dynamic>>>{
    'a': [
      {'id': 'outside', 'title': 'Outside task', 'profile': 'a'},
      {'id': 'loaded', 'title': 'Loaded task', 'profile': 'a'},
    ],
    'b': <Map<String, dynamic>>[],
  };
  List<Map<String, dynamic>> active = [];
  int activeReads = 0;
  bool activeFails = false;
  final failedSearchProfiles = <String>{};

  Future<ProfileDiscovery> discover() async => ProfileDiscovery(
    profiles: const [
      HermesProfile(name: 'a'),
      HermesProfile(name: 'b'),
    ],
    currentName: 'a',
    activeName: 'a',
  );

  ProfileGateway gateway(WorkspaceScope scope) =>
      gateways[scope.profileName] = ProfileGateway(
        scope: scope,
        discover: discover,
        get: (path, query) async {
          if (path == 'sessions/search') {
            if (failedSearchProfiles.contains(scope.profileName)) {
              throw StateError('profile unavailable');
            }
            return {
              'results': (saved[scope.profileName] ?? const [])
                  .where((row) => row['id'] == query['q'])
                  .map(
                    (row) => {
                      'session_id': row['id'],
                      'title': row['title'],
                      'profile': row['profile'],
                    },
                  )
                  .toList(),
            };
          }
          if (path == 'sessions') {
            final rows = saved[scope.profileName] ?? const [];
            return {
              'sessions': rows,
              'offset': int.parse(query['offset']!),
              'limit': int.parse(query['limit']!),
              'total': rows.length,
            };
          }
          return {
            'session_id': path.split('/')[1],
            'messages': <Map<String, dynamic>>[],
            'pagination': {
              'offset': 0,
              'limit': 50,
              'returned': 0,
              'order': 'latest',
            },
          };
        },
        rpc: (method, params) async {
          if (method == 'session.active_list') {
            activeReads++;
            if (activeFails) throw StateError('offline');
            return {'sessions': active};
          }
          if (method == 'projects.tree') return {'projects': []};
          if (method == 'session.create') {
            return {
              'session_id': 'loaded-runtime',
              'stored_session_id': 'loaded',
              'session_key': 'loaded',
              'running': false,
              'info': {'profile_name': scope.profileName},
            };
          }
          return {};
        },
      );

  void changed() => gateways['a']!.onEvent!(
    StreamEvent(type: 'sessions.changed', data: const {}),
  );

  void connection(bool connected) =>
      gateways['a']!.onConnectionChanged!(connected);
}

Future<void> waitForReads(NotificationCoverageHost host, int count) async {
  for (var i = 0; i < 100 && host.activeReads < count; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(host.activeReads, count);
  await Future<void>.delayed(Duration.zero);
}

Map<String, dynamic> row(
  String runtime,
  String session,
  String status, [
  double lastActive = 1,
]) => {
  'id': runtime,
  'session_key': session,
  'status': status,
  'last_active': lastActive,
};

void main() {
  late NotificationCoverageHost host;
  late ProfileWorkspaceController controller;
  late bool disposed;
  late List<({String profile, String session, bool input})> alerts;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = NotificationCoverageHost();
    disposed = false;
    alerts = [];
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Host',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'notification-coverage',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
      onAttention: (chat, input, [_]) async => alerts.add((
        profile: chat.key.workspace.profileName,
        session: chat.key.sessionId,
        input: input,
      )),
    );
    await controller.initialize();
    host.activeReads = 0;
    controller.visible = false;
  });

  tearDown(() {
    if (!disposed) controller.dispose();
  });

  test(
    'alerts for authoritative unopened task transitions without history',
    () async {
      host.active = [row('outside-runtime', 'outside', 'working')];
      host.changed();
      await waitForReads(host, 1);
      expect(alerts, isEmpty, reason: 'the first snapshot is only a baseline');

      host.active = [row('outside-runtime', 'outside', 'waiting', 2)];
      host.changed();
      await waitForReads(host, 2);
      expect(alerts, [(profile: 'a', session: 'outside', input: true)]);

      host.active = [row('outside-runtime', 'outside', 'idle', 3)];
      host.changed();
      await waitForReads(host, 3);
      expect(alerts.last, (profile: 'a', session: 'outside', input: false));

      host.active = [row('outside-runtime', 'outside', 'working', 4)];
      host.changed();
      await waitForReads(host, 4);
      host.active = [row('outside-runtime', 'outside', 'idle', 5)];
      host.changed();
      await waitForReads(host, 5);
      expect(
        alerts.where((alert) => !alert.input),
        hasLength(2),
        reason: 'a later turn on the same runtime is a new transition',
      );
    },
  );

  test('deduplicates loaded event and reconciliation paths', () async {
    final loaded = await controller.createChat();
    host.active = [row(loaded.runtimeId, loaded.key.sessionId, 'working')];
    host.changed();
    await waitForReads(host, 1);

    host.gateways['a']!.onEvent!(
      StreamEvent(
        type: 'clarify',
        sessionId: loaded.runtimeId,
        data: const {'request_id': 'q1', 'question': 'Continue?'},
      ),
    );
    host.active = [row(loaded.runtimeId, loaded.key.sessionId, 'waiting', 2)];
    host.changed();
    await waitForReads(host, 2);

    expect(alerts, [(profile: 'a', session: 'loaded', input: true)]);
  });

  test('failed and reconnected snapshots never imply completion', () async {
    host.active = [row('outside-runtime', 'outside', 'working')];
    host.changed();
    await waitForReads(host, 1);

    host.activeFails = true;
    host.changed();
    await waitForReads(host, 2);
    host.connection(false);
    host.connection(true);
    host.activeFails = false;
    host.active = [];
    host.changed();
    await waitForReads(host, 3);

    expect(alerts, isEmpty);
  });

  for (final status in [null, 'unknown']) {
    test('a $status runtime does not prove completion', () async {
      host.active = [row('outside-runtime', 'outside', 'working')];
      host.changed();
      await waitForReads(host, 1);
      host.active = [
        if (status != null) row('outside-runtime', 'outside', status, 2),
      ];
      host.changed();
      await waitForReads(host, 2);
      expect(alerts, isEmpty);
    });
  }

  test('does not alert without one verified profile owner', () async {
    host.saved['b'] = [
      {'id': 'outside', 'title': 'Collision', 'profile': 'b'},
    ];
    host.active = [row('outside-runtime', 'outside', 'working')];
    host.changed();
    await waitForReads(host, 1);
    host.active = [row('outside-runtime', 'outside', 'idle', 2)];
    host.changed();
    await waitForReads(host, 2);
    expect(alerts, isEmpty);

    host.saved['b'] = [];
    host.failedSearchProfiles.add('b');
    host.active = [row('outside-runtime-2', 'outside', 'working', 3)];
    host.changed();
    await waitForReads(host, 3);
    host.failedSearchProfiles.clear();
    host.active = [row('outside-runtime-2', 'outside', 'idle', 4)];
    host.changed();
    await waitForReads(host, 4);
    expect(
      alerts,
      isEmpty,
      reason: 'a failed ownership read resets the baseline',
    );
  });

  test('disposed controller ignores later invalidations', () async {
    controller.dispose();
    disposed = true;
    host.active = [row('outside-runtime', 'outside', 'working')];
    host.changed();
    await Future<void>.delayed(Duration.zero);
    expect(host.activeReads, 0);
    expect(alerts, isEmpty);
  });
}
