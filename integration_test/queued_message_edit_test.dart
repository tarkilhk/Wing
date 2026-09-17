import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/attachment_draft.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/composer_draft_store.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/composer_action_button.dart';

import '../test/support/profile_actions_fixture.dart';

/// Runs production widgets/controller on Android with no external transport.
/// Install only in the separate Dev package on a disposable emulator.
class _QueueFixture extends ProfileActionsFixture {
  final gateways = <String, ProfileGateway>{};
  final steers = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? steerReply;
  bool rejectSteer = false;

  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    {'id': 1, 'role': 'user', 'content': 'Review the Android conversation UI.'},
    {
      'id': 2,
      'role': 'assistant',
      'content': 'I am checking the composer and queued messages.',
    },
  ];

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return gateways[scope.profileName] = ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: base.read,
      rpc: (method, params) async {
        if (method == 'session.steer') {
          steers.add(Map.of(params));
          return steerReply?.future ??
              {'status': rejectSteer ? 'rejected' : 'queued'};
        }
        if (method == 'file.attach') {
          return {'attached': true, 'ref_text': 'attached:${params['name']}'};
        }
        return base.call(method, params);
      },
    );
  }

  void finish(ProfileChat chat) =>
      gateways[chat.key.workspace.profileName]!.onEvent!(
        StreamEvent(
          type: 'turn.end',
          sessionId: chat.runtimeId,
          data: {'status': 'completed'},
        ),
      );

  List<Map<String, dynamic>> get submissions => calls
      .where((call) => call.$2 == 'prompt.submit')
      .map((call) => call.$3)
      .toList();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  late _QueueFixture fixture;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;
  var convertedSurface = false;
  final composer = find.byKey(const Key('profile-message-composer'));

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!convertedSurface) {
      await binding.convertFlutterSurfaceToImage();
      convertedSurface = true;
      await frames(tester);
    }
    final bytes = await binding.takeScreenshot(name);
    final directory = await getExternalStorageDirectory();
    final frame = File('${directory!.path}/$name.png');
    await frame.writeAsBytes(bytes);
    debugPrint('Native frame: ${frame.path}');
  }

  Future<AttachmentDraft> file(String name) async {
    final directory = await getTemporaryDirectory();
    final cached = File('${directory.path}/$name');
    await cached.writeAsString('Isolated queued-message device test');
    return AttachmentDraft(
      id: name,
      cachedPath: cached.path,
      name: name,
      byteLength: await cached.length(),
      mediaType: 'text/plain',
      kind: AttachmentDraftKind.genericFile,
    );
  }

  Future<void> launch(
    WidgetTester tester, {
    double scale = 1,
    bool light = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: wingTheme(light ? Brightness.light : Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ProfileWorkspaceScreen(controller: controller),
      ),
    );
    await frames(tester);
  }

  Future<void> edit(WidgetTester tester, String original) async {
    final row = find.text(original);
    await tester.ensureVisible(row);
    await tester.longPress(row);
    await frames(tester);
    expect(chat.composerText, original);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Steer'), findsOneWidget);
  }

  setUp(() async {
    convertedSurface = false;
    SharedPreferences.setMockInitialValues({});
    fixture = _QueueFixture();
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'queue-device',
        label: 'Queue device QA',
        host: 'unused',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'isolated-queued-message-device-test',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
    chat.title = 'Queued message device check';
    chat.status = ProfileTurnStatus.running;
    await controller.queuePrompt(chat, 'Review the layout');
    await controller.queuePrompt(chat, 'Then check the tests');
    await controller.updateDraft(
      chat,
      'My unfinished draft\nKeep this second line.',
    );
  });

  tearDown(() => controller.dispose());

  testWidgets(
    'long press opens the native keyboard; Queue restores text and files',
    (tester) async {
      final bufferedFile = await file('draft-notes.txt');
      chat.attachments.add(bufferedFile);
      await launch(tester);
      expect(find.byTooltip('Message actions'), findsNothing);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ComposerActionButton)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await frames(tester);
      expect(
        find.byKey(const ValueKey('composer-choice-queue')),
        findsOneWidget,
      );
      await gesture.cancel();
      await frames(tester);
      expect(
        find.byKey(const ValueKey('composer-action-selector')),
        findsNothing,
      );
      await edit(tester, 'Review the layout');
      // No synthetic viewInsets: this is the real Android IME after focus.
      final keyboardDeadline = DateTime.now().add(const Duration(seconds: 10));
      while (View.of(tester.element(composer)).viewInsets.bottom == 0 &&
          DateTime.now().isBefore(keyboardDeadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        View.of(tester.element(composer)).viewInsets.bottom,
        greaterThan(0),
      );
      expect(find.byTooltip('Delete queued message'), findsOneWidget);
      await capture(tester, 'queue-01-edit-keyboard');
      await tester.enterText(
        composer,
        'Review spacing first\nThen check contrast.',
      );
      await frames(tester);
      await tester.tap(find.text('Queue'));
      await frames(tester);
      expect(chat.queuedPrompts.map((prompt) => prompt.text), [
        'Review spacing first\nThen check contrast.',
        'Then check the tests',
      ]);
      expect(chat.composerText, 'My unfinished draft\nKeep this second line.');
      expect(chat.attachments, [same(bufferedFile)]);
      expect(await File(bufferedFile.cachedPath).exists(), isTrue);
      expect(fixture.submissions, isEmpty);
      await capture(tester, 'queue-02-restored-draft');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cancel restores the draft and discards only the queue edit', (
    tester,
  ) async {
    await launch(tester);
    await edit(tester, 'Review the layout');
    await tester.enterText(composer, 'Discard this modification');
    await frames(tester);
    await tester.tap(find.text('Cancel'));
    await frames(tester);
    expect(chat.queuedPrompts.first.text, 'Review the layout');
    expect(chat.composerText, 'My unfinished draft\nKeep this second line.');
    expect(find.byTooltip('Delete queued message'), findsNothing);
    expect(fixture.steers, isEmpty);
    expect(fixture.submissions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('red cross asks before deleting just the selected instruction', (
    tester,
  ) async {
    await launch(tester);
    await edit(tester, 'Review the layout');
    await tester.tap(find.byTooltip('Delete queued message'));
    await frames(tester);
    await capture(tester, 'queue-03-delete-confirmation');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ),
    );
    await frames(tester);
    expect(chat.queuedPrompts, hasLength(2));
    expect(chat.composerText, 'Review the layout');
    await tester.tap(find.byTooltip('Delete queued message'));
    await frames(tester);
    await tester.tap(find.text('Delete'));
    await frames(tester);
    expect(chat.queuedPrompts.single.text, 'Then check the tests');
    expect(chat.composerText, 'My unfinished draft\nKeep this second line.');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Steer waits for acknowledgement, sends once and restores the draft',
    (tester) async {
      fixture.steerReply = Completer<Map<String, dynamic>>();
      final bufferedFile = await file('steer-buffer.txt');
      chat.attachments.add(bufferedFile);
      await launch(tester);
      await edit(tester, 'Review the layout');
      await tester.enterText(composer, 'Focus on spacing now');
      await frames(tester);
      await tester.tap(find.text('Steer'));
      await frames(tester);
      expect(chat.queueMutating, isTrue);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Steer'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.widget<TextField>(composer).enabled, isFalse);
      expect(fixture.steers, hasLength(1));
      expect(fixture.steers.single['text'], 'Focus on spacing now');
      expect(fixture.steers.single['session_id'], chat.runtimeId);
      final pending =
          await ComposerDraftStore(
            controller.preferences,
            connectionIdentity: 'isolated-queued-message-device-test',
          ).read(
            profileName: chat.key.workspace.profileName,
            sessionId: chat.key.sessionId,
          );
      expect(pending!.queuePaused, isTrue);
      expect(pending.queuedPrompts.first.text, 'Review the layout');
      fixture.steerReply!.complete({'status': 'queued'});
      await frames(tester);
      expect(chat.queuedPrompts.single.text, 'Then check the tests');
      expect(chat.composerText, 'My unfinished draft\nKeep this second line.');
      expect(chat.attachments, [same(bufferedFile)]);
      expect(fixture.submissions, isEmpty);
      expect(find.text('steered'), findsOneWidget);
      await capture(tester, 'queue-04-steered');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rejected and failed steering preserve the edit for recovery', (
    tester,
  ) async {
    fixture.rejectSteer = true;
    await launch(tester);
    await edit(tester, 'Review the layout');
    await tester.enterText(composer, 'Keep this edited instruction');
    await frames(tester);
    await tester.tap(find.text('Steer'));
    await frames(tester);
    expect(chat.queuedPrompts, hasLength(2));
    expect(chat.composerText, 'Keep this edited instruction');
    expect(find.text('Hermes rejected the steering message.'), findsOneWidget);
    fixture.steerReply = Completer<Map<String, dynamic>>();
    await tester.tap(find.text('Steer'));
    await frames(tester);
    fixture.steerReply!.completeError(
      StateError('Device test connection lost'),
    );
    await frames(tester);
    expect(chat.queuedPrompts.first.text, 'Review the layout');
    expect(chat.composerText, 'Keep this edited instruction');
    expect(chat.queuePaused, isTrue);
    expect(chat.draft, 'My unfinished draft\nKeep this second line.');
    expect(find.text('steered'), findsNothing);
    expect(fixture.submissions, isEmpty);
    await capture(tester, 'queue-05-failed-steer');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'turn completion holds the edit then sends the saved version once',
    (tester) async {
      await launch(tester);
      await edit(tester, 'Review the layout');
      await tester.enterText(composer, 'Send only this edited version');
      await frames(tester);
      fixture.finish(chat);
      await frames(tester);
      expect(fixture.submissions, isEmpty);
      expect(chat.composerText, 'Send only this edited version');
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Steer'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Queue'));
      await frames(tester);
      expect(fixture.submissions, hasLength(1));
      expect(
        fixture.submissions.single['text'],
        'Send only this edited version',
      );
      expect(chat.queuedPrompts.single.text, 'Then check the tests');
      expect(chat.composerText, 'My unfinished draft\nKeep this second line.');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'queued attachments survive editing at large text with the keyboard',
    (tester) async {
      final queuedFile = await file('queued-review.txt');
      chat.attachments.add(queuedFile);
      await controller.updateDraft(chat, 'Review this file');
      await controller.queuePrompt(chat, chat.draft);
      await controller.updateDraft(chat, 'Buffered draft');
      await launch(tester, scale: 2, light: true);
      final row = find.text('Review this file · queued-review.txt');
      await tester.ensureVisible(row);
      await tester.longPress(row);
      await frames(tester);
      await tester.enterText(composer, 'Check the attached notes');
      await frames(tester);
      await tester.ensureVisible(find.text('Queue'));
      await capture(tester, 'queue-06-large-text-attachment');
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Steer'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Queue'));
      await frames(tester);
      expect(chat.queuedPrompts.last.text, 'Check the attached notes');
      expect(chat.queuedPrompts.last.attachments, [same(queuedFile)]);
      expect(await File(queuedFile.cachedPath).exists(), isTrue);
      expect(chat.composerText, 'Buffered draft');
      expect(tester.takeException(), isNull);
    },
  );
}
