import 'package:wing/core/widgets/source_code_text.dart';
import 'package:wing/core/services/profile_supervision_session.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:flutter/material.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/activity_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/profile_subagent_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_actions_fixture.dart';
import 'support/composer_fixture.dart' show emitChatEvent;

class _SubagentFixture extends ProfileActionsFixture {
  int listCalls = 0;
  int tailCalls = 0;
  int tailFailures = 0;
  bool acceptSteer = false;
  bool findInterrupt = false;
  bool emptyList = false;
  bool tailAvailable = true;
  double? startedAt;
  List<Map<String, dynamic>>? rows;
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
              'subagents':
                  rows ??
                  [
                    if (!emptyList)
                      {
                        'subagent_id': 'child-1',
                        'goal': 'Inspect the release',
                        'status': 'running',
                        'model': 'test-model',
                        'last_tool': 'read_file',
                        'accepting_steer': true,
                        'started_at': startedAt,
                        'tool_count': 3,
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
              'available': tailAvailable,
              'text': tailAvailable ? 'latest child output' : '',
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
  late AppPreferences appPreferences;
  late ProfileChat chat;
  late ProfileSupervisionSession supervision;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = _SubagentFixture();
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'subagent-panel',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat(canDispatch: () => true);
    supervision = ProfileSupervisionSession(controller: controller, chat: chat);
  });

  tearDown(() {
    supervision.dispose();
    controller.dispose();
    appPreferences.dispose();
  });

  Future<void> showPanel(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1.8,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: [
              ProfileSubagentPanel(
                session: supervision,
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inspect the release'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'agent timing is backend-derived and stops on completion or uncertainty',
    (tester) async {
      fixture.startedAt = DateTime.now().millisecondsSinceEpoch / 1000 - 40;
      await showPanel(tester);
      expect(find.text('Reading file'), findsOneWidget);
      expect(find.text('test-model · 3 tool calls'), findsOneWidget);
      var time = tester.widget<ActivityTime>(find.byType(ActivityTime));
      expect(time.backendStartedAt, fixture.startedAt);
      emitChatEvent(controller, chat, 'subagent.complete', {
        'subagent_id': 'child-1',
        'status': 'completed',
        'summary': 'Inspection finished',
        'duration_seconds': 42.5,
      });
      await tester.pump();
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Inspection finished'), findsOneWidget);
      time = tester.widget<ActivityTime>(find.byType(ActivityTime));
      expect(time.backendStartedAt, isNull);
      expect(time.durationSeconds, 42.5);
      expect(find.text('43 s'), findsOneWidget);
      emitChatEvent(controller, chat, 'subagent.start', {
        'subagent_id': 'uncertain',
        'goal': 'Check another source',
        'started_at': fixture.startedAt,
      });
      fixture.emptyList = true;
      await supervision.refreshSubagents();
      await tester.pump();
      expect(find.text('Last seen running'), findsOneWidget);
      expect(
        tester
            .widgetList<ActivityTime>(find.byType(ActivityTime))
            .every((w) => w.backendStartedAt == null),
        isTrue,
      );
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'agent states and metadata remain readable ${brightness.name} $scale',
        (tester) async {
          const longGoal =
              'Inspect the release candidate and verify the Android transport settings. Keep every original instruction in the task body.';
          const heading =
              'Inspect the release candidate and verify the Android transport settings';
          fixture.rows = [
            {
              'subagent_id': 'child-1',
              'goal': longGoal,
              'status': 'running',
              'last_tool': 'read_file',
              'model': 'test-model',
              'accepting_steer': true,
            },
            {
              'subagent_id': 'queued',
              'goal': 'Compare suppliers',
              'status': 'queued',
              'started_at': 1000,
            },
          ];
          for (final status in ['completed', 'failed', 'interrupted']) {
            emitChatEvent(controller, chat, 'subagent.complete', {
              'subagent_id': status,
              'goal': 'Research $status',
              'status': status,
              'summary': 'Result for $status',
              'duration_seconds': 1.25,
            });
          }
          await showPanel(tester, brightness: brightness, scale: scale);
          final title = tester.widget<Text>(find.text(heading));
          expect(title.maxLines, 2);
          expect(title.overflow, TextOverflow.ellipsis);
          expect(find.text(longGoal), findsNothing);
          expect(
            tester.getSize(find.text(heading)).height,
            lessThanOrEqualTo(2 * 14 * scale * 1.3 + 1),
          );
          for (final label in [
            'Running',
            'Queued',
            'Completed',
            'Failed',
            'Interrupted',
          ]) {
            expect(find.text(label), findsOneWidget);
          }
          final queuedRow = find.byKey(
            ValueKey(('subagent', chat.key, 'queued')),
          );
          final queuedTime = tester.widget<ActivityTime>(
            find.descendant(of: queuedRow, matching: find.byType(ActivityTime)),
          );
          expect(queuedTime.backendStartedAt, isNull);
          expect(queuedTime.durationSeconds, isNull);
          await tester.ensureVisible(find.text(heading));
          await tester.pumpAndSettle();
          await tester.tap(find.text(heading));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text(longGoal), findsOneWidget);
          expect(find.byTooltip('Copy Task'), findsOneWidget);
          Navigator.of(tester.element(find.text(longGoal))).pop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'a terminal tool name is activity context, not a reported result',
    (tester) async {
      fixture.rows = [
        {
          'subagent_id': 'child-1',
          'goal': 'Inspect the release',
          'status': 'completed',
          'last_tool': 'read_file',
        },
      ];
      await openDetails(tester);
      await tester.pumpAndSettle();
      expect(find.text('Reported result'), findsNothing);
      expect(find.textContaining('Last activity:'), findsOneWidget);
      expect(find.byTooltip('Copy Current activity'), findsNothing);
      expect(find.byTooltip('Steer'), findsNothing);
      expect(find.byTooltip('Interrupt'), findsNothing);
      Navigator.of(tester.element(find.text('Task'))).pop();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('backend metadata remains passive beside existing controls', (
    tester,
  ) async {
    await openDetails(tester);
    await tester.ensureVisible(find.byTooltip('Expand Raw details'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand Raw details'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Copy Raw details'), findsNothing);
    expect(find.byTooltip('Open Raw details'), findsNothing);
    expect(find.byTooltip('Wrap Raw details'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SourceCodeText &&
            widget.text.contains('Agent ID: child-1'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Copy Task'), findsOneWidget);
    expect(find.byTooltip('Copy Live output'), findsOneWidget);
    Navigator.of(tester.element(find.text('Raw details'))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('refresh retains two live event children beside a failed child', (
    tester,
  ) async {
    fixture.emptyList = true;
    emitChatEvent(controller, chat, 'subagent.complete', {
      'subagent_id': 'failed',
      'goal': 'Timed out research',
      'status': 'timeout',
    });
    emitChatEvent(controller, chat, 'subagent.start', {
      'subagent_id': 'one',
      'goal': 'Research one',
    });
    emitChatEvent(controller, chat, 'subagent.start', {
      'subagent_id': 'two',
      'goal': 'Research two',
    });
    await showPanel(tester);
    expect(chat.subagents.map((item) => item.id), ['failed', 'one', 'two']);
    expect(find.text('Research one'), findsOneWidget);
    expect(find.text('Research two'), findsOneWidget);
    expect(find.text('1 finished'), findsNothing);
  });

  testWidgets(
    'detail shows received activity when the server has no transcript',
    (tester) async {
      fixture.tailAvailable = false;
      emitChatEvent(controller, chat, 'subagent.start', {
        'subagent_id': 'child-1',
        'goal': 'Inspect the release',
      });
      emitChatEvent(controller, chat, 'subagent.tool', {
        'subagent_id': 'child-1',
        'tool_name': 'read_file',
        'tool_preview': 'Checking android/app/build.gradle.kts',
      });
      await openDetails(tester);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Recent activity'),
        160,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Recent activity'), findsOneWidget);
      expect(find.byTooltip('Copy Live output'), findsNothing);
      expect(find.byTooltip('Open Live output'), findsNothing);
      expect(find.byTooltip('Copy Current activity'), findsNothing);
      expect(find.byTooltip('Refresh live output'), findsOneWidget);
      expect(find.byTooltip('Copy Recent activity'), findsNothing);
      expect(
        find.textContaining('Checking android/app/build.gradle.kts').last,
        findsOneWidget,
      );
      Navigator.of(tester.element(find.text('Live output'))).pop();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'an unavailable tail refresh preserves the output already received',
    (tester) async {
      await openDetails(tester);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byWidgetPredicate(
          (widget) =>
              widget is SourceCodeText && widget.text == 'latest child output',
        ),
        160,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SourceCodeText && widget.text == 'latest child output',
        ),
        findsOneWidget,
      );
      fixture.tailAvailable = false;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SourceCodeText && widget.text == 'latest child output',
        ),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.text('Live output'))).pop();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('shows live tail and keeps rejected steering text', (
    tester,
  ) async {
    await openDetails(tester);

    expect(fixture.tailCalls, 1);
    await tester.scrollUntilVisible(
      find.byWidgetPredicate(
        (widget) =>
            widget is SourceCodeText && widget.text == 'latest child output',
      ),
      160,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SourceCodeText && widget.text == 'latest child output',
      ),
      findsOneWidget,
    );
    expect(find.byType(SourceCodeText), findsWidgets);
    expect(find.byTooltip('Steer'), findsOneWidget);
    expect(find.byTooltip('Interrupt'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byType(TextField),
      -160,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(find.byType(TextField), 'Check the Android path');
    final steerButton = find.byTooltip('Steer');
    await tester.ensureVisible(steerButton);
    await tester.pumpAndSettle();
    await tester.tap(steerButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('The subagent did not accept that steering.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byType(TextField),
      -160,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Check the Android path',
    );
    expect(chat.subagents.single.status.name, 'running');
    final steer = fixture.requests.lastWhere(
      (call) => call.$1 == 'subagent.steer',
    );
    expect(steer.$2['session_id'], chat.runtime.runtimeId);
    expect(steer.$2['subagent_id'], 'child-1');
    expect(steer.$2['text'], 'Check the Android path');

    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'populated event roster refreshes authoritative steering capability',
    (tester) async {
      emitChatEvent(controller, chat, 'subagent.start', {
        'subagent_id': 'child-1',
        'goal': 'Inspect the release',
        'status': 'running',
        'model': 'test-model',
      });
      expect(chat.subagents.single.acceptingSteer, isFalse);

      await showPanel(tester);

      expect(fixture.listCalls, 1);
      expect(chat.subagents.single.acceptingSteer, isTrue);
      await tester.ensureVisible(find.text('Inspect the release'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspect the release'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byTooltip('Steer'), findsOneWidget);

      Navigator.of(tester.element(find.byTooltip('Steer'))).pop();
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
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Could not refresh live output.'), findsOneWidget);
    expect(find.byTooltip('Retry'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(fixture.tailCalls, 3);

    await tester.ensureVisible(find.byTooltip('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(
      find.byWidgetPredicate(
        (widget) =>
            widget is SourceCodeText && widget.text == 'latest child output',
      ),
      160,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SourceCodeText && widget.text == 'latest child output',
      ),
      findsOneWidget,
    );

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
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Inspect the release'), findsOneWidget);
    expect(fixture.listCalls, 1);
  });
}
