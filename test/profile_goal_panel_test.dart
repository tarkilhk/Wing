import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/profile_goal_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_actions_fixture.dart';

class _GoalFixture extends ProfileActionsFixture {
  final requests = <(String, Map<String, dynamic>)>[];
  bool hasGoal = true;
  bool failAction = false;
  final subgoals = <String>['Implement', 'Verify'];

  Map<String, dynamic> get control => {
    'goal': hasGoal
        ? {
            'title': 'Ship the release',
            'status': 'active',
            'turns_used': 2,
            'max_turns': 8,
            'contract': {
              'outcome': 'A useful release',
              'verification': 'Run checks',
              'constraints': 'Keep scope small',
              'boundaries': 'No unrelated edits',
              'stop_when': 'Checks pass',
            },
            'subgoals': subgoals,
            'gates': const [],
          }
        : null,
    'revision': 'goal-revision',
    'updated_at': 1,
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
        if (method == 'session.control.read') return {'control': control};
        if (method == 'session.control') {
          if (failAction) throw StateError('Action rejected');
          final args = params['args'] as Map<String, dynamic>;
          if (params['action'] == 'subgoal.add') {
            subgoals.add(args['text'] as String);
          } else if (params['action'] == 'subgoal.remove') {
            subgoals.removeAt((args['index'] as int) - 1);
          } else if (params['action'] == 'subgoal.clear') {
            subgoals.clear();
          }
          return {
            'control': control,
            'dispatch': {
              'type': 'exec',
              'output': '✓ Goal updated.',
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
  late _GoalFixture fixture;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = _GoalFixture();
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'goal-panel',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
  });

  tearDown(() => controller.dispose());

  Future<void> showPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ProfileGoalPanel(
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
  }

  testWidgets('renders server goal details and sends pause action', (
    tester,
  ) async {
    await showPanel(tester);

    expect(find.text('Ship the release'), findsOneWidget);
    expect(find.text('Verification: Run checks'), findsOneWidget);
    expect(find.text('1. Implement'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(
      fixture.requests.any(
        (request) =>
            request.$1 == 'session.control' &&
            request.$2['action'] == 'goal.pause',
      ),
      isTrue,
    );
  });

  testWidgets('renders an explicit empty server goal state', (tester) async {
    fixture.hasGoal = false;
    await showPanel(tester);
    expect(
      find.text('Hermes has no active goal for this chat.'),
      findsOneWidget,
    );
  });

  testWidgets('adds a trimmed criterion through the scoped control action', (
    tester,
  ) async {
    await showPanel(tester);
    await tester.tap(find.text('Add criterion'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('goal-criterion-draft')),
      '  Release is verified  ',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    final request = fixture.requests.lastWhere(
      (request) => request.$1 == 'session.control',
    );
    expect(request.$2['action'], 'subgoal.add');
    expect(request.$2['args'], {'text': 'Release is verified'});
    expect(request.$2['session_id'], 'runtime');
    expect(find.text('3. Release is verified'), findsOneWidget);
  });

  testWidgets('retains the add draft when the server rejects it', (
    tester,
  ) async {
    fixture.failAction = true;
    await showPanel(tester);
    await tester.tap(find.text('Add criterion'));
    await tester.pumpAndSettle();
    final draft = find.byKey(const ValueKey('goal-criterion-draft'));
    await tester.enterText(draft, 'Keep this criterion');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(draft).controller!.text,
      'Keep this criterion',
    );
    expect(
      find.text('Criterion could not be added. Review it and try again.'),
      findsOneWidget,
    );
    expect(
      fixture.requests.where(
        (request) =>
            request.$1 == 'session.control' &&
            request.$2['action'] == 'subgoal.add',
      ),
      hasLength(1),
    );
  });

  testWidgets('confirms one-based removal and clearing all criteria', (
    tester,
  ) async {
    await showPanel(tester);
    await tester.tap(find.byTooltip('Remove criterion 2'));
    await tester.pumpAndSettle();
    expect(find.text('Remove criterion 2?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('2. Verify'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove criterion 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    final remove = fixture.requests.lastWhere(
      (request) =>
          request.$1 == 'session.control' &&
          request.$2['action'] == 'subgoal.remove',
    );
    expect(remove.$2['args'], {'index': 2});
    expect(find.text('2. Verify'), findsNothing);

    await tester.tap(find.text('Clear criteria'));
    await tester.pumpAndSettle();
    expect(find.text('Clear all criteria?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear criteria'));
    await tester.pumpAndSettle();
    expect(fixture.subgoals, isEmpty);
    expect(find.text('Criteria (0)'), findsOneWidget);
    final clear = fixture.requests.lastWhere(
      (request) =>
          request.$1 == 'session.control' &&
          request.$2['action'] == 'subgoal.clear',
    );
    expect(clear.$2['args'], isEmpty);
  });

  testWidgets('does not remove or clear criteria changed during confirmation', (
    tester,
  ) async {
    await showPanel(tester);

    await tester.tap(find.byTooltip('Remove criterion 1'));
    await tester.pumpAndSettle();
    fixture.subgoals[0] = 'Changed by server';
    await controller.refreshSessionControl(chat);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Criteria changed'), findsOneWidget);
    expect(find.textContaining('Review the refreshed list'), findsOneWidget);
    expect(
      fixture.requests.where(
        (request) =>
            request.$1 == 'session.control' &&
            request.$2['action'] == 'subgoal.remove',
      ),
      isEmpty,
    );
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear criteria'));
    await tester.pumpAndSettle();
    fixture.subgoals.add('Added by server');
    await controller.refreshSessionControl(chat);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear criteria'));
    await tester.pumpAndSettle();

    expect(find.text('Criteria changed'), findsOneWidget);
    expect(
      fixture.requests.where(
        (request) =>
            request.$1 == 'session.control' &&
            request.$2['action'] == 'subgoal.clear',
      ),
      isEmpty,
    );
  });

  testWidgets('add dialog keeps its draft when the parent panel is disposed', (
    tester,
  ) async {
    var showGoalPanel = true;
    late StateSetter updateHost;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return Scaffold(
              body: showGoalPanel
                  ? ProfileGoalPanel(
                      controller: controller,
                      chat: chat,
                      initiallyExpanded: true,
                    )
                  : const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Add criterion'));
    await tester.pumpAndSettle();
    final draft = find.byKey(const ValueKey('goal-criterion-draft'));
    await tester.enterText(draft, 'Keep this local draft');

    updateHost(() => showGoalPanel = false);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<TextField>(draft).controller!.text,
      'Keep this local draft',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();
    expect(
      fixture.requests.where(
        (request) =>
            request.$1 == 'session.control' &&
            request.$2['action'] == 'subgoal.add',
      ),
      isEmpty,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat menu opens server goal details', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chat actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goal').last);
    await tester.pumpAndSettle();
    expect(find.text('Ship the release'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('keeps goal actions usable on a narrow large-text phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: [
              ProfileGoalPanel(
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
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Refresh'));
    await tester.pumpAndSettle();
    final reads = fixture.requests
        .where((r) => r.$1 == 'session.control.read')
        .length;
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(
      fixture.requests.where((r) => r.$1 == 'session.control.read').length,
      reads + 1,
    );
    await tester.ensureVisible(find.text('Add criterion'));
    await tester.tap(find.text('Add criterion'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('goal-criterion-draft')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
