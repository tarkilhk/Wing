import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/models/hermes_profile.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/services/profile_gateway.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/widgets/profile_subagent_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_actions_fixture.dart';

class _SubagentFixture extends ProfileActionsFixture {
  int listCalls = 0;
  int tailCalls = 0;
  int tailFailures = 0;
  bool acceptSteer = false;
  bool findInterrupt = false;
  final requests = <(String, Map<String, dynamic>)>[];

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: base.read,
      rpc: (method, params) async {
        requests.add((method, params));
        switch (method) {
          case 'subagent.list':
            listCalls += 1;
            return {
              'subagents': [
                {
                  'subagent_id': 'child-1',
                  'goal': 'Inspect the release',
                  'status': 'running',
                  'model': 'test-model',
                  'last_tool': 'read_file',
                  'accepting_steer': true,
                },
              ],
              'delegations': const [],
            };
          case 'subagent.tail':
            tailCalls += 1;
            if (tailCalls <= tailFailures) {
              throw StateError('tail unavailable');
            }
            return {
              'subagent_id': 'child-1',
              'available': true,
              'text': 'latest child output',
              'truncated': false,
            };
          case 'subagent.steer':
            return {
              'status': acceptSteer ? 'queued' : 'rejected',
              'subagent_id': 'child-1',
            };
          case 'subagent.interrupt':
            return {'found': findInterrupt, 'subagent_id': 'child-1'};
          default:
            return base.call(method, params);
        }
      },
    );
  }
}

void main() {
  late _SubagentFixture fixture;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = _SubagentFixture();
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'subagent-panel',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
  });

  tearDown(() => controller.dispose());

  Future<void> showPanel(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: [
              ProfileSubagentPanel(
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

  Future<void> openDetails(WidgetTester tester) async {
    await showPanel(tester);
    await tester.ensureVisible(find.text('Inspect the release'));
    await tester.tap(find.text('Inspect the release'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('shows live tail and keeps rejected steering text', (
    tester,
  ) async {
    await openDetails(tester);

    expect(fixture.tailCalls, 1);
    await tester.scrollUntilVisible(
      find.text('latest child output'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('latest child output'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
    expect(find.text('Steer'), findsOneWidget);
    expect(find.text('Interrupt'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pump();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Check the Android path');
    final steerButton = find.widgetWithText(FilledButton, 'Steer');
    await tester.ensureVisible(steerButton);
    await tester.tap(steerButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('The subagent did not accept that steering.'),
      findsOneWidget,
    );
    expect(find.text('Check the Android path'), findsOneWidget);
    expect(chat.subagents.single.status.name, 'running');
    final steer = fixture.requests.lastWhere(
      (call) => call.$1 == 'subagent.steer',
    );
    expect(steer.$2['session_id'], chat.runtimeId);
    expect(steer.$2['subagent_id'], 'child-1');
    expect(steer.$2['text'], 'Check the Android path');

    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'populated event roster refreshes authoritative steering capability',
    (tester) async {
      chat.subagents = [
        GatewaySubagentActivity.fromGatewayEvent('subagent.start', {
          'subagent_id': 'child-1',
          'goal': 'Inspect the release',
          'status': 'running',
          'model': 'test-model',
        })!,
      ];
      expect(chat.subagents.single.acceptingSteer, isFalse);

      await showPanel(tester);

      expect(fixture.listCalls, 1);
      expect(chat.subagents.single.acceptingSteer, isTrue);
      await tester.ensureVisible(find.text('Inspect the release'));
      await tester.tap(find.text('Inspect the release'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Steer'), findsOneWidget);

      Navigator.of(tester.element(find.text('Steer'))).pop();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('tail polling stops after three failures and Retry restarts it', (
    tester,
  ) async {
    fixture.tailFailures = 3;
    await openDetails(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(fixture.tailCalls, 3);
    await tester.scrollUntilVisible(
      find.text('Could not refresh live output.'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Could not refresh live output.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(fixture.tailCalls, 3);

    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(
      find.text('latest child output'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('latest child output'), findsOneWidget);

    Navigator.of(tester.element(find.text('Live output'))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('Chat actions opens this chat subagent roster', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Inspect the release'), findsNothing);

    await tester.tap(find.byTooltip('Chat actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subagents'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('Inspect the release').last);

    expect(find.text('Inspect the release'), findsOneWidget);
    expect(fixture.listCalls, 1);
  });
}
