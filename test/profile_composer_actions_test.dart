import 'package:wing/core/models/app_preferences.dart';
import 'package:wing/core/models/chat_runtime.dart';
import 'support/composer_fixture.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/attachment_draft.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/queued_prompt_draft.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_actions_fixture.dart';
import 'package:wing/core/models/composer_action.dart';
import 'package:wing/core/widgets/composer_action_button.dart';

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
      rpc: (method, params) => switch (method) {
        'session.steer' => steerReply?.future ?? Future.value(steerResult),
        'commands.catalog' => Future.value({
          'pairs': [
            ['/steer', 'Steer the current turn'],
          ],
        }),
        _ => base.call(method, params),
      },
    );
  }
}

void main() {
  late _ComposerActionsFixture fixture;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = _ComposerActionsFixture();
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'composer-actions',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
  });

  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });

  Future<void> pumpFrames(WidgetTester tester, {int count = 8}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> choose(WidgetTester tester, String action) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ComposerActionButton)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(
      tester.getCenter(find.byKey(ValueKey('composer-choice-$action'))),
    );
    await tester.pump();
    await gesture.up();
    await pumpFrames(tester, count: 4);
  }

  Future<ProfileChat> show(
    WidgetTester tester, {
    double scale = 1,
    ChatExecution status = ChatExecution.idle,
    String draft = '',
    List<String> queued = const [],
    List<AttachmentDraft> attachments = const [],
    bool paused = false,
  }) async {
    final chat = await controller.createChat(canDispatch: () => true);
    if (status == ChatExecution.running) {
      emitChatEvent(controller, chat, 'message.start');
    } else if (status != ChatExecution.idle) {
      throw StateError('Unsupported render fixture state');
    }
    await tester.runAsync(
      () => restoreComposerFixture(
        chat: chat,
        preferences: controller.preferences,
        text: draft,
        attachments: attachments,
        queuedPrompts: queued.map((text) => QueuedPromptDraft(text: text)),
        paused: paused,
      ),
    );
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (const bool.fromEnvironment('CAPTURE_COMPOSER')) {
      await tester.runAsync(() async {
        const fonts = String.fromEnvironment('CAPTURE_FONT_DIR');
        for (final font in {
          'Roboto': 'roboto-regular.ttf',
          'MaterialIcons': 'materialicons-regular.otf',
        }.entries) {
          final loader = FontLoader(font.key)
            ..addFont(
              File(
                '$fonts/${font.value}',
              ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
            );
          await loader.load();
        }
      });
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('composer-preview'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: const bool.fromEnvironment('CAPTURE_COMPOSER')
              ? ThemeData.dark().copyWith(
                  textTheme: ThemeData.dark().textTheme.apply(
                    fontFamily: 'Roboto',
                  ),
                )
              : null,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: ProfileWorkspaceScreen(controller: controller),
        ),
      ),
    );
    await pumpFrames(tester);
    return chat;
  }

  testWidgets('long press edits in the composer and reveals delete', (
    tester,
  ) async {
    final chat = await show(
      tester,
      queued: ['Keep this queued'],
      draft: 'My draft',
      paused: true,
    );
    expect(find.byTooltip('Message actions'), findsNothing);
    await tester.longPress(find.text('Keep this queued'));
    await pumpFrames(tester, count: 4);
    expect(chat.composer.observation.queue.single.text, 'Keep this queued');
    expect(chat.composer.observation.text, 'My draft');
    expect(chat.composer.observation.displayedText, 'Keep this queued');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Steer'), findsOneWidget);
    expect(find.byTooltip('Delete queued message'), findsOneWidget);
    expect(find.byTooltip('Message actions'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('profile-message-composer')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
  });

  testWidgets('configured Stop remains a normal tap action', (tester) async {
    await appPreferences.setRunningAction(ComposerAction.stop);
    await show(tester, status: ChatExecution.running);
    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
    expect(fixture.calls.any((call) => call.$2 == 'session.interrupt'), isTrue);
    expect(find.text('Queue for the next turn'), findsNothing);
  });

  testWidgets('running draft exposes held selector with the keyboard open', (
    tester,
  ) async {
    final chat = await show(
      tester,
      status: ChatExecution.running,
      draft: 'Follow this direction',
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await pumpFrames(tester, count: 4);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Steer')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    for (final action in ['steer', 'stop', 'queue', 'fork']) {
      expect(find.byKey(ValueKey('composer-choice-$action')), findsOneWidget);
    }
    if (const bool.fromEnvironment('CAPTURE_COMPOSER')) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('composer-preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'build/composer-held-selector.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(chat.composer.observation.text, 'Follow this direction');
    expect(
      fixture.calls.any((call) => call.$2 == 'session.interrupt'),
      isFalse,
    );
    await gesture.cancel();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('configured Queue is used without changing future selections', (
    tester,
  ) async {
    await appPreferences.setRunningAction(ComposerAction.queue);
    final chat = await show(
      tester,
      status: ChatExecution.running,
      draft: 'Later',
    );
    await tester.tap(find.byTooltip('Queue'));
    await pumpFrames(tester);
    expect(chat.composer.observation.queue.single.text, 'Later');
    expect(chat.composer.observation.text, isEmpty);
    expect(
      controller.preferences.getString(
        AppPreferenceField.runningAction.storageKey,
      ),
      'queue',
    );
  });

  testWidgets('running chats allow choosing files for the next draft', (
    tester,
  ) async {
    await show(tester, status: ChatExecution.running);
    await tester.tap(find.byTooltip('Attach file'));
    await pumpFrames(tester, count: 4);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await pumpFrames(tester);
  });

  testWidgets('Held slide queues the draft and clears the composer', (
    tester,
  ) async {
    final chat = await show(
      tester,
      status: ChatExecution.running,
      draft: 'follow up after this turn',
    );
    await choose(tester, 'queue');
    expect(
      fixture.calls.any((call) => call.$2 == 'session.interrupt'),
      isFalse,
    );

    expect(
      chat.composer.observation.queue.single.text,
      'follow up after this turn',
    );
    expect(chat.composer.observation.text, isEmpty);
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
      status: ChatExecution.running,
      draft: 'Focus on the failing test',
    );
    await tester.tap(find.byTooltip('Steer'));
    await pumpFrames(tester, count: 4);
    expect(chat.composer.observation.text, isEmpty);
    expect(find.text('steered'), findsOneWidget);
    expect(find.text('Focus on the failing test'), findsOneWidget);
    expect(find.byIcon(Icons.explore_outlined), findsOneWidget);
  });

  testWidgets('slash steer shows only its centered confirmation', (
    tester,
  ) async {
    final chat = await show(
      tester,
      status: ChatExecution.running,
      draft: '/steer Keep the data clean',
    );
    await controller.send(chat);
    await pumpFrames(tester);
    expect(chat.runtime.error, isNull);
    expect(
      chat.reading.messages
          .where((row) => row['_command_notice'] == true)
          .map((row) => row['content']),
      isEmpty,
    );
    expect(find.text('steered'), findsOneWidget);
    expect(find.text('Keep the data clean'), findsOneWidget);
    expect(find.text('Steering message queued.'), findsNothing);
  });

  testWidgets('Held slide queues an attachment-only draft by filename', (
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
      status: ChatExecution.running,
      attachments: [file],
    );
    await choose(tester, 'queue');
    expect(
      chat.composer.observation.queue.single.attachments.map((file) => file.id),
      [file.id],
    );
    expect(chat.composer.observation.attachments, isEmpty);
    expect(find.text('report.pdf'), findsOneWidget);

    await tester.tap(find.text('report.pdf'));
    await pumpFrames(tester, count: 4);
    expect(find.text('Queued: Attachment'), findsOneWidget);
    expect(find.text('1 attachment: report.pdf'), findsOneWidget);
  });

  testWidgets('delete cross confirms deletion and restores the draft', (
    tester,
  ) async {
    final chat = await show(
      tester,
      queued: ['Delete this'],
      draft: 'Separate draft',
      paused: true,
    );
    await tester.longPress(find.text('Delete this'));
    await pumpFrames(tester, count: 4);
    await tester.tap(find.byTooltip('Delete queued message'));
    await pumpFrames(tester, count: 4);
    expect(find.text('Delete queued instruction?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ),
    );
    await pumpFrames(tester, count: 4);
    expect(chat.composer.observation.queue, hasLength(1));
    expect(chat.composer.observation.displayedText, 'Delete this');
    await tester.tap(find.byTooltip('Delete queued message'));
    await pumpFrames(tester, count: 4);
    await tester.tap(find.text('Delete'));
    await pumpFrames(tester, count: 4);
    expect(chat.composer.observation.queue, isEmpty);
    expect(chat.composer.observation.displayedText, 'Separate draft');
    expect(find.text('Editing queued message'), findsNothing);
  });

  testWidgets('composer queue edit cancels or saves in place', (tester) async {
    final chat = await show(
      tester,
      queued: ['Original', 'Second'],
      draft: 'Separate draft',
      paused: true,
    );
    final editor = find.byKey(const Key('profile-message-composer'));
    await tester.longPress(find.text('Original'));
    await pumpFrames(tester, count: 4);
    await tester.enterText(editor, 'Discarded edit');
    await tester.tap(find.text('Cancel'));
    await pumpFrames(tester, count: 4);
    expect(chat.composer.observation.queue.first.text, 'Original');
    expect(chat.composer.observation.displayedText, 'Separate draft');
    await tester.longPress(find.text('Original'));
    await pumpFrames(tester, count: 4);
    await tester.enterText(editor, '');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Queue'))
          .onPressed,
      isNull,
    );
    await tester.enterText(editor, 'Updated');
    await tester.pump();
    await tester.tap(find.text('Queue'));
    await pumpFrames(tester, count: 4);
    expect(chat.composer.observation.queue.map((prompt) => prompt.text), [
      'Updated',
      'Second',
    ]);
    expect(chat.composer.observation.displayedText, 'Separate draft');
    expect(find.text('Editing queued message'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edited steering replaces only the selected queued instruction', (
    tester,
  ) async {
    final chat = await show(
      tester,
      status: ChatExecution.running,
      queued: ['Original', 'Second'],
      draft: 'Separate draft',
    );
    await tester.longPress(find.text('Original'));
    await pumpFrames(tester, count: 4);
    await tester.enterText(
      find.byKey(const Key('profile-message-composer')),
      'Changed direction',
    );
    await tester.tap(find.text('Steer'));
    await pumpFrames(tester, count: 4);
    expect(chat.composer.observation.queue.map((prompt) => prompt.text), [
      'Second',
    ]);
    expect(chat.composer.observation.displayedText, 'Separate draft');
    expect(find.text('Changed direction'), findsOneWidget);
    expect(find.text('steered'), findsOneWidget);
  });

  testWidgets('rejected queued steer keeps the edit and the buffered draft', (
    tester,
  ) async {
    fixture.steerResult = {'status': 'rejected'};
    final chat = await show(
      tester,
      status: ChatExecution.running,
      queued: ['Original'],
      draft: 'Separate draft',
    );
    await tester.longPress(find.text('Original'));
    await pumpFrames(tester, count: 4);
    await tester.enterText(
      find.byKey(const Key('profile-message-composer')),
      'Try this',
    );
    await tester.tap(find.text('Steer'));
    await pumpFrames(tester, count: 4);
    expect(chat.composer.observation.queue.single.text, 'Original');
    expect(chat.composer.observation.displayedText, 'Try this');
    expect(chat.composer.observation.text, 'Separate draft');
    expect(find.text('steered'), findsNothing);
    expect(find.text('Hermes rejected the steering message.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    fixture.steerResult = {'status': 'queued'};
    await tester.tap(find.text('Steer'));
    await pumpFrames(tester, count: 4);
    expect(chat.composer.observation.queue, isEmpty);
    expect(chat.composer.observation.displayedText, 'Separate draft');
    expect(find.text('steered'), findsOneWidget);
  });

  testWidgets('queue editing fits large text with the keyboard open', (
    tester,
  ) async {
    await show(tester, scale: 2.4, queued: ['Original'], paused: true);
    await tester.longPress(find.text('Original'));
    await pumpFrames(tester, count: 4);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await pumpFrames(tester, count: 4);
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Steer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejected steer leaves the typed draft intact', (tester) async {
    fixture.steerResult = {'status': 'rejected'};
    final chat = await show(
      tester,
      status: ChatExecution.running,
      draft: 'keep this if Hermes rejects it',
    );
    await tester.tap(find.byTooltip('Steer'));
    await pumpFrames(tester, count: 4);
    expect(chat.composer.observation.text, 'keep this if Hermes rejects it');
    expect(find.text('steered'), findsNothing);
    expect(find.text('Hermes rejected the steering message.'), findsOneWidget);
  });

  testWidgets(
    'accepted steer preserves a draft edited away and back while held',
    (tester) async {
      fixture.steerReply = Completer<Map<String, dynamic>>();
      final chat = await show(
        tester,
        status: ChatExecution.running,
        draft: 'Check the timeout',
      );
      await tester.tap(find.byTooltip('Steer'));
      await pumpFrames(tester, count: 4);
      expect(chat.composer.observation.steering, isTrue);
      expect(find.text('steered'), findsNothing);
      final field = find.byKey(const Key('profile-message-composer'));
      await tester.enterText(field, 'A different intended message');
      await tester.pump();
      await tester.enterText(field, 'Check the timeout');
      await tester.pump();
      fixture.steerReply!.complete({'status': 'queued'});
      await pumpFrames(tester, count: 4);
      expect(
        chat.reading.messages.where((row) => row['display_kind'] == 'steer'),
        hasLength(1),
      );
      expect(chat.composer.observation.text, 'Check the timeout');
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Check the timeout',
      );
    },
  );

  testWidgets('steer waits for acceptance and preserves a newer draft', (
    tester,
  ) async {
    fixture.steerReply = Completer<Map<String, dynamic>>();
    final chat = await show(
      tester,
      status: ChatExecution.running,
      draft: 'Check the timeout',
    );
    await tester.tap(find.byTooltip('Steer'));
    await pumpFrames(tester, count: 4);
    expect(find.text('steered'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('profile-message-composer')),
      'A separate follow-up',
    );
    fixture.steerReply!.complete({'status': 'queued'});
    await pumpFrames(tester, count: 4);
    expect(chat.composer.observation.text, 'A separate follow-up');
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
      status: ChatExecution.running,
      draft: 'Keep this draft',
    );
    await tester.tap(find.byTooltip('Steer'));
    await pumpFrames(tester, count: 4);
    fixture.steerReply!.completeError(StateError('Connection lost'));
    await pumpFrames(tester, count: 4);
    expect(chat.composer.observation.text, 'Keep this draft');
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

  testWidgets('large text scale keeps the held selector bounded', (
    tester,
  ) async {
    await show(
      tester,
      scale: 2.4,
      status: ChatExecution.running,
      draft: 'Steer me',
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await pumpFrames(tester, count: 4);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Steer')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.byKey(const ValueKey('composer-action-selector')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await gesture.cancel();
    await tester.pump();
  });
}
