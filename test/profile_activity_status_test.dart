import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/profile_transcript.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/widgets/profile_activity_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  late Host host;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = Host()..running = false;
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'activity-status',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
  });

  tearDown(() => controller.dispose());

  String label() => ProfileActivityStatus(chat: chat).label;

  test('latest main event replaces writing and completed tool activity', () {
    host.event('a', 'message.start');
    host.event('a', 'message.delta', {'text': 'I will check.'});
    expect(label(), 'Writing response…');
    host.event('a', 'reasoning.delta', {'text': 'Planning the next step'});
    expect(label(), 'Thinking…');
    host.event('a', 'tool.generating', {'name': 'web_search'});
    expect(label(), 'Preparing Web search');
    host.event('a', 'tool.start', {'name': 'web_search'});
    host.event('a', 'tool.progress', {
      'name': 'web_search',
      'preview': 'Checking accommodation',
    });
    expect(label(), 'Using Web search · Checking accommodation');
    host.event('a', 'tool.complete', {'name': 'web_search'});
    expect(label(), 'Hermes is working…');
    // Accumulated text and reasoning remain in the transcript, not the status.
    expect(chat.streaming, isNotEmpty);
    expect(chat.reasoning, isNotEmpty);
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
    host.event('a', 'tool.progress', {
      'tool_id': 'one',
      'preview': 'Reading results',
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
    host.event('a', 'clarify', {'question': 'Which city?'});
    expect(label(), 'Waiting for your reply');
    host.event('a', 'approval.request', {'command': 'Check a file'});
    expect(label(), 'Waiting for your approval');
    chat.status = ProfileTurnStatus.reconnecting;
    expect(label(), 'Reconnecting… · checking current activity');
    chat.status = ProfileTurnStatus.completed;
    expect(label(), 'Waiting for 1 subagent…');
    host.event('a', 'subagent.complete', {
      'subagent_id': 'child',
      'status': 'completed',
    });
    expect(label(), 'Waiting for your message');
  });

  test('same-name tools show latest progress after a third call completes', () {
    host.event('a', 'message.start');
    host.event('a', 'tool.start', {'name': 'web_search', 'tool_id': 'one'});
    host.event('a', 'tool.start', {'name': 'web_search', 'tool_id': 'two'});
    host.event('a', 'tool.start', {'name': 'read_file', 'tool_id': 'three'});
    host.event('a', 'tool.progress', {
      'tool_id': 'one',
      'preview': 'Latest search progress',
    });
    expect(label(), 'Using Web search · Latest search progress');
    host.event('a', 'tool.complete', {'tool_id': 'three'});
    expect(label(), 'Using Web search · Latest search progress');
  });

  test('a new submission clears the previous execution phase', () async {
    host.event('a', 'message.start');
    host.event('a', 'tool.start', {'name': 'web_search'});
    chat.status = ProfileTurnStatus.completed;
    chat.draft = 'Next question';
    await controller.send(chat);
    expect(label(), 'Hermes is working…');
    expect(chat.tool, isNull);
  });

  test('preparation before tool ID assignment does not leave phantom work', () {
    host.event('a', 'message.start');
    host.event('a', 'tool.generating', {'name': 'web_search'});
    host.event('a', 'tool.start', {'name': 'web_search', 'tool_id': 'one'});
    host.event('a', 'tool.complete', {'tool_id': 'one'});
    expect(label(), 'Hermes is working…');
    expect(chat.toolActivities.where((item) => !item.isTerminal), isEmpty);
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
    expect(find.text('Waiting for your message'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ShaderMask), findsNothing);
    host.event('a', 'message.start');
    host.event('a', 'reasoning.delta', {'text': 'Planning'});
    await tester.pump();
    expect(find.text('Thinking…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget);
    host.event('a', 'clarify', {'question': 'Which city?'});
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
    chat.messages = List.generate(
      30,
      (i) => {
        'id': i,
        'role': 'user',
        'content': 'Message $i with enough text to fill the history.',
      },
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
      'detail': 'Searching many sources for a very long accommodation request',
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
    expect(find.byTooltip(label()), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
