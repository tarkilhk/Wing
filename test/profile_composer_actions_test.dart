import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/models/hermes_profile.dart';
import 'package:hermes_android/core/models/queued_prompt_draft.dart';
import 'package:hermes_android/core/services/profile_gateway.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_actions_fixture.dart';

class _ComposerActionsFixture extends ProfileActionsFixture {
  Map<String, dynamic> steerResult = {'status': 'queued'};
  Completer<Map<String, dynamic>>? steerReply;
  List<Map<String, dynamic>> transcript = [];

  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) =>
      transcript;

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: base.read,
      rpc: (method, params) => method == 'session.steer'
          ? steerReply?.future ?? Future.value(steerResult)
          : base.call(method, params),
    );
  }
}

void main() {
  late _ComposerActionsFixture fixture;
  late ProfileWorkspaceController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = _ComposerActionsFixture();
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'composer-actions',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
  });

  tearDown(() => controller.dispose());

  Future<void> pumpFrames(WidgetTester tester, {int count = 8}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ProfileChat> show(
    WidgetTester tester, {
    double scale = 1,
    ProfileTurnStatus status = ProfileTurnStatus.idle,
    String draft = '',
    List<String> queued = const [],
    List<AttachmentDraft> attachments = const [],
    bool paused = false,
  }) async {
    final chat = await controller.createChat();
    chat.status = status;
    chat.draft = draft;
    chat.attachments.addAll(attachments);
    chat.queuedPrompts.addAll(
      queued.map((text) => QueuedPromptDraft(text: text)),
    );
    chat.queuePaused = paused;
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ProfileWorkspaceScreen(controller: controller),
      ),
    );
    await pumpFrames(tester);
    return chat;
  }

  testWidgets('opening a queued item offers actions without removing it', (
    tester,
  ) async {
    final chat = await show(tester, queued: ['Keep this queued'], paused: true);
    await tester.tap(find.text('Keep this queued'));
    await pumpFrames(tester, count: 4);
    await tester.tap(find.widgetWithText(ListTile, 'Queued: Keep this queued'));
    await pumpFrames(tester, count: 4);
    expect(chat.queuedPrompts.single.text, 'Keep this queued');
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('normal tap remains Stop when the turn is busy', (tester) async {
    await show(tester, status: ProfileTurnStatus.running);
    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
    expect(fixture.calls.any((call) => call.$2 == 'session.interrupt'), isTrue);
    expect(find.text('Queue for the next turn'), findsNothing);
  });

  testWidgets('running chats allow choosing files for the next draft', (
    tester,
  ) async {
    await show(tester, status: ProfileTurnStatus.running);
    await tester.tap(find.byTooltip('Attach file'));
    await pumpFrames(tester, count: 4);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await pumpFrames(tester);
  });

  testWidgets('Message actions queues the draft and clears the composer', (
    tester,
  ) async {
    final chat = await show(
      tester,
      status: ProfileTurnStatus.running,
      draft: 'follow up after this turn',
    );
    await tester.tap(find.byTooltip('Message actions'));
    await pumpFrames(tester, count: 4);
    await tester.tap(find.text('Queue for the next turn'));
    await pumpFrames(tester, count: 4);
    expect(chat.queuedPrompts.single.text, 'follow up after this turn');
    expect(chat.draft, isEmpty);
    final preview = find.text('follow up after this turn');
    expect(preview, findsOneWidget);
    expect(tester.widget<Text>(preview).style?.fontStyle, FontStyle.italic);
    expect(find.byIcon(Icons.keyboard_return), findsOneWidget);
    expect(
      tester.getBottomLeft(preview).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('conversation-composer')))
            .dy,
      ),
    );
  });

  testWidgets('accepted steer immediately shows its text in the transcript', (
    tester,
  ) async {
    final chat = await show(
      tester,
      status: ProfileTurnStatus.running,
      draft: 'Focus on the failing test',
    );
    await tester.tap(find.byTooltip('Message actions'));
    await pumpFrames(tester, count: 4);
    await tester.tap(find.text('Steer this turn'));
    await pumpFrames(tester, count: 4);
    expect(chat.draft, isEmpty);
    expect(find.text('steered'), findsOneWidget);
    expect(find.text('Focus on the failing test'), findsOneWidget);
    expect(find.byIcon(Icons.explore_outlined), findsOneWidget);
  });

  testWidgets('Message actions queues an attachment-only draft by filename', (
    tester,
  ) async {
    final file = AttachmentDraft(
      id: 'report',
      cachedPath: 'report.pdf',
      name: 'report.pdf',
      byteLength: 10,
      mediaType: 'application/pdf',
      kind: AttachmentDraftKind.genericFile,
    );
    final chat = await show(
      tester,
      status: ProfileTurnStatus.running,
      attachments: [file],
    );
    await tester.tap(find.byTooltip('Message actions'));
    await pumpFrames(tester, count: 4);
    await tester.tap(find.text('Queue for the next turn'));
    await pumpFrames(tester, count: 4);
    expect(chat.queuedPrompts.single.attachments, [same(file)]);
    expect(chat.attachments, isEmpty);
    expect(find.text('report.pdf'), findsOneWidget);

    await tester.tap(find.byTooltip('Message actions'));
    await pumpFrames(tester, count: 4);
    expect(find.text('Queued: Attachment'), findsOneWidget);
    expect(find.text('1 attachment: report.pdf'), findsOneWidget);
  });

  testWidgets(
    'queued deletion requires confirmation and cancel keeps the message',
    (tester) async {
      final chat = await show(
        tester,
        queued: ['review this queued item'],
        paused: true,
      );
      await tester.tap(find.byTooltip('Message actions'));
      await pumpFrames(tester, count: 4);
      expect(find.text('Queued messages are paused'), findsOneWidget);
      expect(find.text('Queued: review this queued item'), findsOneWidget);
      await tester.tap(find.text('Queued: review this queued item'));
      await pumpFrames(tester, count: 4);
      expect(chat.queuedPrompts, hasLength(1));
      await tester.tap(find.text('Delete'));
      await pumpFrames(tester, count: 4);
      expect(find.text('Delete queued message?'), findsOneWidget);
      expect(chat.queuedPrompts, hasLength(1));
      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester, count: 4);
      expect(chat.queuedPrompts, hasLength(1));
      await tester.tap(find.byTooltip('Message actions'));
      await pumpFrames(tester, count: 4);
      await tester.tap(find.text('Queued: review this queued item'));
      await pumpFrames(tester, count: 4);
      await tester.tap(find.text('Delete'));
      await pumpFrames(tester, count: 4);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(chat.queuedPrompts, isEmpty);
      expect(find.text('review this queued item'), findsNothing);
    },
  );

  testWidgets('editing a queued message saves in place and cancel keeps it', (
    tester,
  ) async {
    final chat = await show(
      tester,
      queued: ['Original', 'Second'],
      draft: 'Separate draft',
      paused: true,
    );
    Future<void> openEditor() async {
      await tester.tap(find.byTooltip('Message actions'));
      await pumpFrames(tester, count: 4);
      await tester.tap(find.text('Queued: Original'));
      await pumpFrames(tester, count: 4);
      await tester.tap(find.text('Edit'));
      await pumpFrames(tester, count: 4);
    }

    final editor = find.byKey(const ValueKey('queued-message-editor'));
    await openEditor();
    await tester.enterText(editor, 'Discarded edit');
    await tester.tap(find.text('Cancel'));
    await pumpFrames(tester, count: 4);
    expect(chat.queuedPrompts.first.text, 'Original');
    await openEditor();
    await tester.enterText(editor, '');
    await tester.tap(find.text('Save'));
    await pumpFrames(tester, count: 4);
    expect(find.text('Enter a message.'), findsOneWidget);
    expect(chat.queuedPrompts.first.text, 'Original');
    await tester.enterText(editor, 'Updated');
    await tester.tap(find.text('Save'));
    await pumpFrames(tester, count: 4);
    expect(chat.queuedPrompts.map((prompt) => prompt.text), [
      'Updated',
      'Second',
    ]);
    expect(chat.draft, 'Separate draft');
    expect(find.text('Edit queued message'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejected steer leaves the typed draft intact', (tester) async {
    fixture.steerResult = {'status': 'rejected'};
    final chat = await show(
      tester,
      status: ProfileTurnStatus.running,
      draft: 'keep this if Hermes rejects it',
    );
    await tester.tap(find.byTooltip('Message actions'));
    await pumpFrames(tester, count: 4);
    await tester.tap(find.text('Steer this turn'));
    await pumpFrames(tester, count: 4);
    expect(chat.draft, 'keep this if Hermes rejects it');
    expect(find.text('steered'), findsNothing);
    expect(find.text('Hermes rejected the steering message.'), findsOneWidget);
  });

  testWidgets('steer waits for acceptance and preserves a newer draft', (
    tester,
  ) async {
    fixture.steerReply = Completer<Map<String, dynamic>>();
    final chat = await show(
      tester,
      status: ProfileTurnStatus.running,
      draft: 'Check the timeout',
    );
    await tester.tap(find.byTooltip('Message actions'));
    await pumpFrames(tester, count: 4);
    await tester.tap(find.text('Steer this turn'));
    await pumpFrames(tester, count: 4);
    expect(find.text('steered'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('profile-message-composer')),
      'A separate follow-up',
    );
    fixture.steerReply!.complete({'status': 'queued'});
    await pumpFrames(tester, count: 4);
    expect(chat.draft, 'A separate follow-up');
    expect(find.text('Check the timeout'), findsOneWidget);
    expect(find.text('steered'), findsOneWidget);

    fixture.transcript = [
      {
        'id': 42,
        'role': 'user',
        'display_kind': 'steer',
        'content':
            '[OUT-OF-BAND USER MESSAGE — a direct message from the user, delivered once at this position; not tool output and not a new delivery when replayed from conversation history]\nCheck the timeout\n[/OUT-OF-BAND USER MESSAGE]',
      },
    ];
    await controller.refreshHistory(chat);
    await pumpFrames(tester, count: 4);
    expect(find.text('steered'), findsOneWidget);
    expect(find.text('Check the timeout'), findsOneWidget);
    expect(find.textContaining('OUT-OF-BAND'), findsNothing);
  });

  testWidgets('a failed steer does not claim success or clear the draft', (
    tester,
  ) async {
    fixture.steerReply = Completer<Map<String, dynamic>>();
    final chat = await show(
      tester,
      status: ProfileTurnStatus.running,
      draft: 'Keep this draft',
    );
    await tester.tap(find.byTooltip('Message actions'));
    await pumpFrames(tester, count: 4);
    await tester.tap(find.text('Steer this turn'));
    await pumpFrames(tester, count: 4);
    fixture.steerReply!.completeError(StateError('Connection lost'));
    await pumpFrames(tester, count: 4);
    expect(chat.draft, 'Keep this draft');
    expect(find.text('steered'), findsNothing);
    expect(find.textContaining('Connection lost'), findsOneWidget);
  });

  testWidgets(
    'queued rows stay bounded with large text and open queue actions',
    (tester) async {
      await show(
        tester,
        scale: 2.4,
        paused: true,
        queued: ['First follow-up', 'Second follow-up', 'Third follow-up'],
      );
      expect(find.text('Queue paused'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('First follow-up'));
      await pumpFrames(tester, count: 4);
      expect(find.text('Queued messages are paused'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Queued: First follow-up'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await pumpFrames(tester, count: 4);
      expect(find.text('Queued: First follow-up'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large text scale keeps the actions sheet bounded', (
    tester,
  ) async {
    await show(tester, scale: 2.4, queued: ['first', 'second', 'third']);
    await tester.tap(find.byTooltip('Message actions'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Queued: first'), findsOneWidget);
  });
}
