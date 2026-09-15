import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/profile_background_work_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_actions_fixture.dart';

class _BackgroundFixture extends ProfileActionsFixture {
  final requests = <(String, Map<String, dynamic>)>[];
  bool running = true;
  bool rejectStop = false;
  String loopStatus = 'active';
  String heartbeatStatus = 'active';
  bool heartbeatPresent = true;

  List<Map<String, dynamic>> get processes => [
    if (running)
      {
        'session_id': 'proc-running',
        'command': 'dart run worker.dart',
        'cwd': '/workspace',
        'output_tail': 'waiting for work\n',
        'status': 'running',
        'uptime_seconds': 125,
        'pid': 4321,
        'detached': true,
        'notify_on_complete': true,
      },
    {
      'session_id': 'proc-exited',
      'command': 'dart test',
      'output_tail': 'All tests passed.\n',
      'status': 'exited',
      'exit_code': 0,
      'uptime_seconds': 9,
    },
  ];

  Map<String, dynamic> get control => {
    'goal': null,
    'loop': {
      'prompt': 'Check the release queue',
      'status': loopStatus,
      'mode': 'interval',
      'interval_seconds': 300,
      'current_delay': 300,
      'times': 6,
      'until': '',
      'max_ticks': 0,
      'ticks_fired': 3,
      'created_at': 1,
      'last_fired_at': 2,
      'next_due_at': 1893456000,
      'awaiting_response': true,
      'deferred_by_goal': true,
    },
    'heartbeat': heartbeatPresent
        ? {
            'prompt': 'Report deployment health',
            'status': heartbeatStatus,
            'interval_seconds': 900,
            'created_at': 1,
            'last_fired_at': 2,
            'fire_count': 4,
          }
        : null,
    'revision': 'background-revision',
    'updated_at': 3,
  };

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: base.read,
      rpc: (method, params) async {
        requests.add((method, params));
        if (method == 'process.list') return {'processes': processes};
        if (method == 'process.kill') {
          if (rejectStop) {
            return {'status': 'error', 'process_id': params['process_id']};
          }
          running = false;
          return {'status': 'killed', 'session_id': params['process_id']};
        }
        if (method == 'session.control.read') return {'control': control};
        if (method == 'session.control') {
          if (params['action'] == 'loop.pause') loopStatus = 'paused';
          if (params['action'] == 'heartbeat.pause') {
            heartbeatStatus = 'paused';
          }
          if (params['action'] == 'heartbeat.clear') heartbeatPresent = false;
          return {
            'control': control,
            'dispatch': {
              'type': 'exec',
              'output': 'Background work updated.',
              'notice': null,
              'message': null,
              'display': null,
            },
          };
        }
        return base.call(method, params);
      },
    );
  }
}

void main() {
  late _BackgroundFixture fixture;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = _BackgroundFixture();
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'background-work-panel',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
  });

  tearDown(() => controller.dispose());

  Future<void> showPanel(
    WidgetTester tester, {
    Size size = const Size(800, 900),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: [
              ProfileBackgroundWorkPanel(
                controller: controller,
                chat: chat,
                initiallyExpanded: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  testWidgets('stops only the selected running process after server ACK', (
    tester,
  ) async {
    await showPanel(tester);
    await tester.tap(find.text('dart run worker.dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop process'));
    await tester.pumpAndSettle();

    final stop = fixture.requests.singleWhere(
      (request) => request.$1 == 'process.kill',
    );
    expect(stop.$2['process_id'], 'proc-running');
    expect(stop.$2['session_id'], 'runtime');
    expect(find.text('dart run worker.dart'), findsNothing);
    expect(find.text('dart test'), findsOneWidget);
  });

  testWidgets('keeps a rejected process and dismisses only an exited row', (
    tester,
  ) async {
    fixture.rejectStop = true;
    await showPanel(tester);

    await tester.tap(find.text('dart run worker.dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop process'));
    await tester.pumpAndSettle();
    expect(find.text('dart run worker.dart'), findsOneWidget);
    expect(
      find.text('The server did not confirm that the process stopped.'),
      findsOneWidget,
    );

    await tester.tap(find.text('dart test'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Dismiss'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('dart test'), findsNothing);
    expect(
      fixture.requests.where((request) => request.$1 == 'process.kill'),
      hasLength(1),
    );
  });

  testWidgets('keeps recurring controls usable on a narrow large-text phone', (
    tester,
  ) async {
    await showPanel(tester, size: const Size(320, 640), textScale: 1.8);
    expect(tester.takeException(), isNull);
    expect(chat.sessionControlError, isNull);
    expect(chat.sessionControl, isNotNull);
    expect(find.text('3/6 runs'), findsOneWidget);
    expect(find.text('Waiting for the current response'), findsOneWidget);
    expect(find.text('Deferred while the goal is active'), findsOneWidget);

    await tester.ensureVisible(find.text('Pause loop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause loop'));
    await tester.pumpAndSettle();
    expect(
      fixture.requests.any(
        (request) =>
            request.$1 == 'session.control' &&
            request.$2['action'] == 'loop.pause',
      ),
      isTrue,
    );

    await tester.ensureVisible(find.text('Clear heartbeat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear heartbeat'));
    await tester.pumpAndSettle();
    expect(find.text('Clear heartbeat?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(
      fixture.requests.any(
        (request) =>
            request.$1 == 'session.control' &&
            request.$2['action'] == 'heartbeat.clear',
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat actions opens background work for the current chat', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chat actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Background work').last);
    await tester.pumpAndSettle();

    expect(find.text('Check the release queue'), findsOneWidget);
    expect(find.text('Report deployment health'), findsOneWidget);
    expect(find.text('dart run worker.dart'), findsOneWidget);
  });
}
