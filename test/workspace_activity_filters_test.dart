import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/profile_live_activity.dart';
import 'package:wing/core/screens/workspace_overview_content.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ActivityHost {
  final live = <String, List<Map<String, dynamic>>>{};
  final failed = <String>{};

  Future<ProfileDiscovery> discover() async => ProfileDiscovery(
    profiles: [const HermesProfile(name: 'main')],
    currentName: 'main',
    activeName: 'main',
  );

  ProfileGateway gateway(WorkspaceScope scope) => ProfileGateway(
    scope: scope,
    discover: discover,
    connect: () async {},
    get: (path, query) async => path == 'sessions/search'
        ? {
            'results': [
              for (final row in const [
                {'id': 'running', 'title': 'Running job', 'profile': 'main'},
                {'id': 'needs-input', 'title': 'Question', 'profile': 'main'},
                {
                  'id': 'side-work',
                  'title': 'Deploy checks',
                  'profile': 'main',
                },
                {
                  'id': 'idle-old',
                  'title': 'Idle old server',
                  'profile': 'main',
                },
              ])
                if (row['id'] == query['q'])
                  {
                    'session_id': row['id'],
                    'title': row['title'],
                    'profile': row['profile'],
                  },
            ],
          }
        : path == 'sessions'
        ? {
            'sessions': [
              {'id': 'running', 'title': 'Running job', 'profile': 'main'},
              {'id': 'needs-input', 'title': 'Question', 'profile': 'main'},
              {'id': 'side-work', 'title': 'Deploy checks', 'profile': 'main'},
              {'id': 'idle-old', 'title': 'Idle old server', 'profile': 'main'},
            ],
            'offset': int.parse(query['offset']!),
            'limit': int.parse(query['limit']!),
            'total': 2,
          }
        : {
            'session_id': path.split('/')[1],
            'messages': <Map<String, dynamic>>[],
            'pagination': {
              'offset': 0,
              'limit': 50,
              'returned': 0,
              'order': 'latest',
            },
          },
    rpc: (method, params) async {
      if (method == 'session.active_list') {
        if (failed.contains(scope.profileName)) throw StateError('offline');
        return {'sessions': live[scope.profileName] ?? []};
      }
      if (method == 'projects.tree') return {'projects': []};
      return {};
    },
  );
}

void main() {
  late _ActivityHost host;
  late ProfileWorkspaceController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = _ActivityHost();
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Host',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'activity-filter-test',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    host.live['main'] = [
      {
        'id': 'runtime-running',
        'session_key': 'running',
        'status': 'working',
        'last_active': 2,
      },
      {
        'id': 'runtime-input',
        'session_key': 'needs-input',
        'status': 'waiting',
        'last_active': 1,
        'side_tasks_running': 0,
      },
      {
        'id': 'runtime-side',
        'session_key': 'side-work',
        'status': 'idle',
        'last_active': 3,
        'side_tasks_running': 2,
      },
      {
        'id': 'runtime-idle-old',
        'session_key': 'idle-old',
        'status': 'idle',
        'last_active': 4,
      },
    ];
    await controller.refreshActivity();
  });

  tearDown(() => controller.dispose());

  testWidgets('filters activity, opens an owner item, and fits large text', (
    tester,
  ) async {
    ProfileLiveActivity? opened;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          home: SizedBox(
            width: 320,
            child: Scaffold(
              body: WorkspaceActivityContent(
                controller: controller,
                onOpen: (item) => opened = item,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Running job'), findsOneWidget);
    expect(find.text('Question'), findsOneWidget);
    expect(find.text('Deploy checks'), findsOneWidget);
    expect(find.textContaining('2 background tasks running'), findsOneWidget);
    expect(find.text('Idle old server'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Needs input'));
    await tester.pump();
    expect(find.text('Running job'), findsNothing);
    expect(find.text('Question'), findsOneWidget);
    await tester.tap(find.text('Question'));
    expect(opened?.sessionId, 'needs-input');

    await tester.tap(find.widgetWithText(FilterChip, 'Running'));
    await tester.pump();
    expect(find.text('Running job'), findsOneWidget);
    expect(find.text('Question'), findsNothing);
    expect(find.text('Deploy checks'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'All'));
    await tester.pump();
    expect(find.text('Question'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retains activity-unavailable error', (tester) async {
    host.failed.add('main');
    await controller.refreshActivity();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceActivityContent(
            controller: controller,
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Activity unavailable.'), findsOneWidget);
    expect(find.text('No ongoing sessions'), findsNothing);
  });
}
