import 'package:wing/core/services/chat_runtime.dart';
import 'support/composer_fixture.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/models/chat_runtime.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/profile_transcript.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/profile_activity_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  late Host host;
  late ProfileWorkspaceController controller;
  late WorkspaceRuntimeFixture runtimes;
  late AppPreferences appPreferences;
  late ProfileChat chat;
  late ChatRuntime runtime;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    runtimes = WorkspaceRuntimeFixture();
    host = Host()..running = false;
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'activity-status',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
      runtimeFactory: runtimes.create,
    );
    await controller.initialize();

    chat = await openFixtureChat(
      controller: controller,
      key: ProfileSessionKey(controller.current!.scope, 'same'),
      title: 'Activity',
    );
    runtime = runtimes.forChat(chat);
  });

  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });

  String? label() => ProfileActivityStatus(chat: chat).label;

  test(
    'idle and cancelled hide while other status messages remain available',
    () {
      for (final status in [
        ChatExecution.idle,
        ChatExecution.completed,
        ChatExecution.cancelled,
      ]) {
        switch (status) {
          case ChatExecution.idle:
            runtime.resetCompleted();
          case ChatExecution.completed:
            runtime.completeTurn(failed: false, cancelled: false, error: null);
          case ChatExecution.cancelled:
            runtime.completeTurn(failed: false, cancelled: true, error: null);
          default:
            throw StateError('Unexpected fixture execution');
        }
        expect(label(), isNull);
      }
      runtime.reportError('History failed');
      expect(label(), 'History needs attention');
      runtime.reportError(null);
      runtime.beginCommand();
      expect(label(), 'Running command…');
      runtime.finishCommand();
      host.event('a', 'subagent.start', {'subagent_id': 'child'});
      expect(label(), 'Waiting for 1 subagent…');
      for (final entry in {
        ChatExecution.submitting: 'Sending message…',
        ChatExecution.failed: 'Something went wrong',
      }.entries) {
        if (entry.key == ChatExecution.submitting) {
          runtime.beginTurn(submitting: true);
        } else {
          runtime.failTurn('Turn failed');
        }
        expect(label(), entry.value);
      }
    },
  );

  testWidgets('activity expands and fades, then fully collapses on cancel', (
    tester,
  ) async {
    Future<void> render({bool reducedMotion = false}) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: Scaffold(
            body: Column(children: [ProfileActivityStatus(chat: chat)]),
          ),
        ),
      ),
    );
    final row = find.byType(ProfileActivityStatus);
    await render();
    expect(tester.getSize(row).height, 0);
    runtime.beginTurn(submitting: false);
    await render();
    expect(tester.getSize(row).height, 0);
    await tester.pump(const Duration(milliseconds: 60));
    final entering = tester.getSize(row).height;
    expect(entering, greaterThan(0));
    expect(
      tester
          .widget<FadeTransition>(find.byType(FadeTransition).last)
          .opacity
          .value,
      inExclusiveRange(0, 1),
    );
    await tester.pump(const Duration(milliseconds: 200));
    final expanded = tester.getSize(row).height;
    expect(expanded, greaterThan(entering));

    runtime.completeTurn(failed: false, cancelled: true, error: null);
    await render();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getSize(row).height, inExclusiveRange(0, expanded));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getSize(row).height, 0);
    expect(find.text('Stopped'), findsNothing);
    expect(find.text('Hermes is working…'), findsNothing);

    // A quick new turn during collapse must restore the current status.
    runtime.beginTurn(submitting: false);
    await render();
    await tester.pump(const Duration(milliseconds: 60));
    runtime.completeTurn(failed: false, cancelled: true, error: null);
    await render();
    await tester.pump(const Duration(milliseconds: 40));
    runtime.failTurn('Turn failed');
    await render();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Hermes is working…'), findsNothing);

    await render(reducedMotion: true);
    runtime.completeTurn(failed: false, cancelled: true, error: null);
    await render(reducedMotion: true);
    expect(tester.getSize(row).height, 0);
    runtime.beginTurn(submitting: false);
    await render(reducedMotion: true);
    expect(tester.getSize(row).height, expanded);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('latest main event replaces writing and completed tool activity', () {
    host.event('a', 'message.start');
    host.event('a', 'message.delta', {'text': 'I will check.'});
    expect(label(), 'Writing response…');
    host.event('a', 'reasoning.delta', {'text': 'Planning the next step'});
    expect(label(), 'Thinking…');
    host.event('a', 'tool.generating', {'name': 'web_search'});
    expect(label(), 'Preparing Web search');
    host.event('a', 'tool.start', {
      'tool_id': 'search',
      'name': 'web_search',
      'context': 'Checking accommodation',
    });
    expect(label(), 'Using Web search · Checking accommodation');
    host.event('a', 'tool.complete', {
      'tool_id': 'search',
      'name': 'web_search',
    });
    expect(label(), 'Hermes is working…');
    // Accumulated text and reasoning remain in the transcript, not the status.
    expect(chat.reading.streaming, isNotEmpty);
    expect(chat.runtime.reasoning, isNotEmpty);
    host.event('a', 'message.delta', {'text': 'Here are the results.'});
    host.event('a', 'reasoning.available', {'text': 'Earlier reasoning'});
    expect(label(), 'Writing response…');
    host.event('a', 'message.interim');
    expect(label(), 'Hermes is working…');
  });

  test('parallel tools retain current work when another tool completes', () {
    host.event('a', 'message.start');
    host.event('a', 'tool.start', {'name': 'web_search', 'tool_id': 'one'});
    host.event('a', 'tool.start', {'name': 'read_file', 'tool_id': 'two'});
    host.event('a', 'tool.complete', {'name': 'read_file', 'tool_id': 'two'});
    expect(label(), 'Using Web search');
    host.event('a', 'tool.start', {
      'tool_id': 'one',
      'name': 'web_search',
      'context': 'Reading results',
    });
    expect(label(), 'Using Web search · Reading results');
    host.event('a', 'message.delta', {'text': 'Result'});
    host.event('a', 'tool.complete', {'tool_id': 'one'});
    expect(label(), 'Writing response…');
  });

  test('child updates never replace main activity or an input request', () {
    host.event('a', 'message.start');
    host.event('a', 'reasoning.delta', {'text': 'Planning'});
    host.event('a', 'subagent.start', {'subagent_id': 'child'});
    host.event('a', 'subagent.tool', {
      'subagent_id': 'child',
      'tool': 'read_file',
    });
    expect(label(), 'Thinking… · 1 subagent active');
    host.event('a', 'clarify', {
      'request_id': 'city',
      'question': 'Which city?',
    });
    expect(label(), 'Waiting for your reply');
    host.event('a', 'approval', {
      'request_id': 'file',
      'server_request_id': 'file-server',
      'command': 'Check a file',
    });
    expect(label(), 'Waiting for your approval');
    runtime.beginRecovery();
    expect(label(), 'Reconnecting… · checking current activity');
    runtime.recovered();
    runtime.reconcileOpenRequests(const []);
    runtime.cancelRequest({'id': 'file-server', 'method': 'approval'});
    runtime.completeTurn(failed: false, cancelled: false, error: null);
    expect(label(), 'Waiting for 1 subagent…');
    host.event('a', 'subagent.complete', {
      'subagent_id': 'child',
      'status': 'completed',
    });
    expect(label(), isNull);
  });

  test(
    'same-name tools retain latest context after a third call completes',
    () {
      host.event('a', 'message.start');
      host.event('a', 'tool.start', {'name': 'web_search', 'tool_id': 'one'});
      host.event('a', 'tool.start', {'name': 'web_search', 'tool_id': 'two'});
      host.event('a', 'tool.start', {'name': 'read_file', 'tool_id': 'three'});
      host.event('a', 'tool.start', {
        'tool_id': 'one',
        'name': 'web_search',
        'context': 'Latest search context',
      });
      expect(label(), 'Using Web search · Latest search context');
      host.event('a', 'tool.complete', {'tool_id': 'three'});
      expect(label(), 'Using Web search · Latest search context');
    },
  );

  test('a new submission clears the previous execution phase', () async {
    host.event('a', 'message.start');
    host.event('a', 'tool.start', {'name': 'web_search'});
    runtime.recovered();
    runtime.reconcileOpenRequests(const []);
    runtime.cancelRequest({'id': 'file-server', 'method': 'approval'});
    runtime.completeTurn(failed: false, cancelled: false, error: null);
    chat.composer.editText('Next question');
    await controller.send(chat);
    expect(label(), 'Hermes is working…');
    expect(chat.runtime.tool, isNull);
  });

  test('preparation before tool ID assignment does not leave phantom work', () {
    host.event('a', 'message.start');
    host.event('a', 'tool.generating', {'name': 'web_search'});
    host.event('a', 'tool.start', {'name': 'web_search', 'tool_id': 'one'});
    host.event('a', 'tool.complete', {'tool_id': 'one'});
    expect(label(), 'Hermes is working…');
    expect(
      chat.runtime.toolActivities.where((item) => !item.isTerminal),
      isEmpty,
    );
  });

  test(
    'reconnect waits for fresh activity instead of reusing old text',
    () async {
      host.event('a', 'message.start');
      host.event('a', 'tool.start', {'name': 'web_search'});
      host.running = true;
      host.inflight = {'assistant': 'Previous partial text', 'streaming': true};
      await controller.reconnect(chat.key.workspace);
      expect(label(), 'Hermes is working…');
      host.event('a', 'reasoning.delta', {'text': 'Next step'});
      expect(label(), 'Thinking…');
    },
  );

  testWidgets('live events update the row and stop animation for input', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => ProfileActivityStatus(chat: chat),
          ),
        ),
      ),
    );
    expect(find.text('Waiting for your message'), findsNothing);
    expect(tester.getSize(find.byType(ProfileActivityStatus)).height, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ShaderMask), findsNothing);
    host.event('a', 'message.start');
    host.event('a', 'reasoning.delta', {'text': 'Planning'});
    await tester.pump();
    expect(find.text('Thinking…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget);
    host.event('a', 'clarify', {
      'request_id': 'city',
      'question': 'Which city?',
    });
    await tester.pump();
    expect(find.text('Waiting for your reply'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('status stays below scrolling history and above the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    chat.reading.installSavedHistory(
      List.generate(
        30,
        (i) => {
          'id': i,
          'role': 'user',
          'content': 'Message $i with enough text to fill the history.',
        },
      ),
    );
    host.event('a', 'message.start');
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final status = find.byKey(const ValueKey('profile-activity-status'));
    final composer = find.byKey(const ValueKey('conversation-composer'));
    final transcript = find.byType(ProfileTranscript);
    expect(
      tester.getBottomLeft(transcript).dy,
      lessThanOrEqualTo(tester.getTopLeft(status).dy),
    );
    expect(
      tester.getBottomLeft(status).dy,
      lessThanOrEqualTo(tester.getTopLeft(composer).dy),
    );
    final position = tester.getTopLeft(status);
    await tester.drag(transcript, const Offset(0, 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getTopLeft(status), position);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pump();
    expect(tester.getBottomLeft(composer).dy, lessThanOrEqualTo(500));
    expect(
      tester.getBottomLeft(status).dy,
      lessThanOrEqualTo(tester.getTopLeft(composer).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('long status fits large text and respects reduced motion', (
    tester,
  ) async {
    host.event('a', 'message.start');
    host.event('a', 'tool.start', {
      'name': 'web_search',
      'context': 'Searching many sources for a very long accommodation request',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: SizedBox(
              width: 320,
              child: ProfileActivityStatus(chat: chat),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byTooltip(label()!), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
