import 'package:wing/core/models/chat_runtime.dart';
import 'support/composer_fixture.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/answer_versions.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/models/queued_prompt_draft.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/profile_message.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'answer_versions_test.dart' show AnswerHost;

const _capture = bool.fromEnvironment('STUDIO_REVIEW');
const _reviewFrame = ValueKey('saved-edit-review-frame');

void main() {
  late AnswerHost host;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;
  late ProfileChat original;

  setUpAll(() async {
    if (!_capture) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'Ahem': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            Future.value(
              ByteData.sublistView(File(entry.value).readAsBytesSync()),
            ),
          ))
          .load();
    }
  });

  Future<void> capture(WidgetTester tester, String name) async {
    if (!_capture) return;
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_reviewFrame),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('/tmp/wing-message-edit-review')
        ..createSync(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    host = AnswerHost();
    controller = ProfileWorkspaceController(
      connectionIdentity: 'host-settings',
      access: ConnectionAccess(
        connection: SavedConnection(
          id: 'host',
          label: 'Host',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        dashboardOAuth: null,
      ),
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    await controller.openSession(
      ProfileSessionKey(controller.current!.scope, 'original'),
    );
    original = controller.current!.chat!;
  });

  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });

  testWidgets('edit stays on sent messages and out of Fork and Find', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-message-4')), findsOneWidget);
    expect(find.byTooltip('Edit prompt'), findsNothing);
    final reading = controller.openReadingSession(original);
    addTearDown(reading.dispose);
    await reading.start();
    reading.search('Follow-up');
    expect(reading.select(reading.observation.matches.single), isTrue);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit message'), findsNothing);
    expect(host.calls.where((call) => call.$1 == 'prompt.submit'), isEmpty);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('${brightness.name} edit dialog at $scale above keyboard', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpWidget(
          RepaintBoundary(
            key: _reviewFrame,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: wingTheme(brightness),
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
        await tester.pumpAndSettle();
        final edit = find.byKey(const ValueKey('edit-message-4'));
        if (edit.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            edit,
            160,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        tester.view.viewInsets = FakeViewPadding(
          bottom: 240 * tester.view.devicePixelRatio,
        );
        await tester.pumpAndSettle();
        final submit = find.widgetWithText(FilledButton, 'Replace and resend');
        final close = find.byTooltip('Cancel editing');
        expect(tester.getRect(submit).bottom, lessThanOrEqualTo(400));
        expect(tester.getRect(close).top, greaterThanOrEqualTo(0));
        expect(tester.getSize(close), const Size(48, 48));
        expect(tester.takeException(), isNull);
        await capture(tester, 'editor-${brightness.name}-$scale');
        final field = find.byKey(const ValueKey('saved-message-edit-input'));
        await tester.ensureVisible(field);
        await tester.enterText(field, 'Corrected follow-up');
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
        host.submitError = JsonRpcError(
          'prompt.submit',
          'Session busy',
          code: 4009,
        );
        await tester.tap(submit);
        for (var i = 0; i < 100 && original.runtime.changingAnswer; i++) {
          await tester.pump(const Duration(milliseconds: 1));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
        }
        await tester.pumpAndSettle();
        final error = find.byKey(const ValueKey('edit-message-error'));
        await tester.ensureVisible(error);
        await tester.pumpAndSettle();
        expect(tester.widget<TextFormField>(field).enabled, isTrue);
        expect(tester.getRect(submit).bottom, lessThanOrEqualTo(400));
        expect(tester.getRect(close).top, greaterThanOrEqualTo(0));
        expect(
          tester.getRect(find.text('Edit message')).top,
          greaterThanOrEqualTo(0),
        );
        expect(tester.takeException(), isNull);
        await capture(tester, 'editor-error-${brightness.name}-$scale');
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('saved-message-edit-dialog')),
          findsNothing,
        );
      });
    }
  }

  test('unchanged and empty edits do not rewind or pause the queue', () async {
    await restoreComposerFixture(
      chat: original,
      preferences: controller.preferences,
      appendQueued: [QueuedPromptDraft(text: 'Queued followup')],
    );
    final prompt = original.reading.messages.first;
    for (final text in ['', '  ', ' Original prompt ']) {
      expect(await controller.editSavedPrompt(original, prompt, text), isFalse);
    }
    expect(host.calls.where((call) => call.$1 == 'prompt.submit'), isEmpty);
    expect(original.composer.observation.paused, isFalse);
    expect(original.reading.messages.first, prompt);
  });

  test('edit rewinds the addressed row and pauses queued followups', () async {
    await controller.updateDraft(original, 'Unrelated composer draft');
    await restoreComposerFixture(
      chat: original,
      preferences: controller.preferences,
      appendQueued: [QueuedPromptDraft(text: 'Queued followup')],
    );

    final accepted = await controller.editSavedPrompt(
      original,
      original.reading.messages.first,
      'Corrected prompt',
    );

    expect(accepted, isTrue);
    expect(host.calls.lastWhere((call) => call.$1 == 'prompt.submit').$2, {
      'session_id': 'runtime-original',
      'profile': 'a',
      'text': 'Corrected prompt',
      'truncate_before_row_id': 1,
      'confirm_truncate': true,
      'confirm_empty_truncate': true,
    });
    expect(original.composer.observation.text, 'Unrelated composer draft');
    expect(original.composer.observation.queue.single.text, 'Queued followup');
    expect(original.composer.observation.paused, isTrue);
    expect(original.reading.messages.map(answerMessageText), [
      'Corrected prompt',
    ]);
  });

  test('rejected edit restores history and keeps local work paused', () async {
    await controller.updateDraft(original, 'Keep this draft');
    await restoreComposerFixture(
      chat: original,
      preferences: controller.preferences,
      appendQueued: [QueuedPromptDraft(text: 'Keep this queued message')],
    );
    final before = List<Map<String, dynamic>>.of(original.reading.messages);
    final statusBefore = original.runtime.execution;
    final serverHistoryBefore = host
        .history('a', 'original')
        .map(Map<String, dynamic>.of)
        .toList();
    host.submitError = JsonRpcError(
      'prompt.submit',
      'Session busy',
      code: 4009,
    );

    final accepted = await controller.editSavedPrompt(
      original,
      original.reading.messages.first,
      'Rejected correction',
    );

    expect(accepted, isFalse);
    expect(original.reading.messages, before);
    expect(original.composer.observation.text, 'Keep this draft');
    expect(
      original.composer.observation.queue.single.text,
      'Keep this queued message',
    );
    expect(original.composer.observation.paused, isTrue);
    expect(original.runtime.execution, statusBefore);
    expect(host.history('a', 'original'), serverHistoryBefore);
    expect(
      host.calls.where((call) => call.$1 == 'prompt.submit'),
      hasLength(1),
    );
    expect(original.runtime.reconnecting, isFalse);
  });

  test('lost edit acknowledgement is not reported as success', () async {
    await controller.updateDraft(original, 'Keep this unrelated draft');
    host.submitError = TimeoutException('connection lost');

    final accepted = await controller.editSavedPrompt(
      original,
      original.reading.messages.first,
      'Possibly delivered correction',
    );

    expect(accepted, isFalse);
    expect(original.runtime.reconnecting, isTrue);
    expect(original.composer.observation.text, 'Keep this unrelated draft');
    expect(original.runtime.error, contains('uncertain'));
  });

  for (final failure in [
    JsonRpcError('prompt.submit', 'Timeout', reason: 'request_timeout'),
    JsonRpcError(
      'prompt.submit',
      'Connection closed',
      reason: 'connection_closed',
    ),
    JsonRpcError('prompt.submit', 'Internal error', code: -32603),
    JsonRpcError(
      'prompt.submit',
      'Session storage could not be written',
      code: 5071,
    ),
  ]) {
    test(
      'edit reconciles accepted history after ${failure.reason ?? failure.code}',
      () async {
        await controller.updateDraft(original, 'Unrelated draft');
        await restoreComposerFixture(
          chat: original,
          preferences: controller.preferences,
          appendQueued: [QueuedPromptDraft(text: 'Keep queued followup')],
        );
        host.submitError = failure;
        host.submitErrorAfterAcceptance = true;

        final accepted = await controller.editSavedPrompt(
          original,
          original.reading.messages.first,
          'Delivered correction',
        );

        expect(accepted, isFalse);
        expect(original.runtime.reconnecting, isTrue);
        expect(original.runtime.error, contains('uncertain'));
        expect(original.reading.messages.map(answerMessageText), [
          'Delivered correction',
        ]);
        expect(original.composer.observation.paused, isTrue);

        host.resumeDelay = Completer<void>();
        final recovery = controller.reconnect(original.key.workspace);
        await controller.updateDraft(original, 'New draft during recovery');
        host.resumeDelay!.complete();
        await recovery;

        expect(original.reading.messages.map(answerMessageText), [
          'Delivered correction',
          'New answer 0',
        ]);
        expect(original.composer.observation.text, 'New draft during recovery');
        expect(
          original.composer.observation.queue.single.text,
          'Keep queued followup',
        );
        expect(original.composer.observation.paused, isTrue);
        expect(original.runtime.execution, ChatExecution.completed);
        expect(
          host.calls.where((call) => call.$1 == 'prompt.submit'),
          hasLength(1),
        );
      },
    );
  }

  test('fork sends once after the latest saved answer', () async {
    await controller.updateDraft(original, 'Continue in a fork');

    final child = await controller.forkPrompt(
      original,
      original.composer.observation.text,
    );

    expect(child, isNotNull);
    final forked = child!;
    expect(host.calls.lastWhere((call) => call.$1 == 'session.branch').$2, {
      'session_id': 'runtime-original',
      'profile': 'a',
      'count': 4,
    });
    expect(host.calls.lastWhere((call) => call.$1 == 'prompt.submit').$2, {
      'session_id': forked.runtime.runtimeId,
      'profile': 'a',
      'text': 'Continue in a fork',
    });
    expect(original.composer.observation.text, isEmpty);
    expect(forked.runtime.execution, ChatExecution.running);
  });

  test('failed fork send leaves the source draft intact', () async {
    await controller.updateDraft(original, 'Do not lose this');
    host.submitError = JsonRpcError(
      'prompt.submit',
      'Session busy',
      code: 4009,
    );

    final child = await controller.forkPrompt(
      original,
      original.composer.observation.text,
    );

    expect(child, isNotNull);
    final forked = child!;
    expect(original.composer.observation.text, 'Do not lose this');
    expect(forked.runtime.reconnecting, isTrue);
    expect(original.runtime.error, contains('Check the child chat'));
    expect(
      host.calls.where((call) => call.$1 == 'prompt.submit'),
      hasLength(1),
    );
  });

  testWidgets('saved user edit requires explicit history replacement', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    final edit = find.byKey(const ValueKey('edit-message-4'));
    await tester.ensureVisible(edit);
    final target = tester.getRect(edit);
    expect(target.width, greaterThanOrEqualTo(48));
    expect(target.height, greaterThanOrEqualTo(48));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final prompt = find.ancestor(
      of: edit,
      matching: find.byType(ProfileMessage),
    );
    final copy = find.descendant(
      of: prompt,
      matching: find.byTooltip('Copy message'),
    );
    final copyTarget = tester.getRect(copy);
    expect(copyTarget.size, const Size(48, 48));
    await tester.tapAt(Offset(copyTarget.right - 2, copyTarget.bottom - 2));
    await tester.pumpAndSettle();
    expect(copied, 'Follow-up');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(edit);
    final visibleTarget = tester.getRect(edit);
    await tester.tapAt(
      Offset(visibleTarget.right - 2, visibleTarget.center.dy),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit message'), findsOneWidget);
    expect(
      find.text(
        "Resending replaces this message and all later history in this chat.",
      ),
      findsOneWidget,
    );
    expect(find.text('Follow-up'), findsWidgets);
    expect(find.text('Replace and resend'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Cancel editing'));
    await tester.pumpAndSettle();
    expect(host.calls.where((call) => call.$1 == 'prompt.submit'), isEmpty);
  });

  testWidgets('rejected edit keeps the correction in the dialog', (
    tester,
  ) async {
    host.submitError = JsonRpcError(
      'prompt.submit',
      'Session busy',
      code: 4009,
    );
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    final edit = find.byKey(const ValueKey('edit-message-4'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Corrected followup');
    await tester.pump();
    await tester.tap(find.text('Replace and resend'));
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && original.runtime.changingAnswer; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    await tester.pump();

    expect(find.text('Edit message'), findsOneWidget);
    expect(find.text('Corrected followup'), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-message-error')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('edit-message-error')),
        matching: find.text('Hermes did not accept the edited message.'),
      ),
      findsOneWidget,
    );
  });

  for (final rejected in [false, true]) {
    testWidgets(
      'pending saved edit blocks dismissal and input until ${rejected ? 'refusal' : 'acceptance'}',
      (tester) async {
        host.submitDelay = Completer<void>();
        if (rejected) {
          host.submitError = JsonRpcError(
            'prompt.submit',
            'Session busy',
            code: 4009,
          );
        }
        await tester.pumpWidget(
          MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
        );
        await tester.pumpAndSettle();
        final edit = find.byKey(const ValueKey('edit-message-4'));
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('saved-message-edit-input'));
        await tester.enterText(field, 'Retained correction');
        await tester.pump();
        await tester.tap(find.text('Replace and resend'));
        await tester.pump();
        for (
          var i = 0;
          i < 100 && !host.calls.any((call) => call.$1 == 'prompt.submit');
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 1));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
        }
        expect(
          host.calls.where((call) => call.$1 == 'prompt.submit'),
          hasLength(1),
        );
        expect(original.runtime.changingAnswer, isTrue);
        expect(tester.widget<TextFormField>(field).enabled, isFalse);
        await tester.tapAt(const Offset(8, 8));
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text('Edit message'), findsOneWidget);
        expect(
          find.descendant(
            of: field,
            matching: find.text('Retained correction'),
          ),
          findsOneWidget,
        );
        host.submitDelay!.complete();
        for (var i = 0; i < 100 && original.runtime.changingAnswer; i++) {
          await tester.pump(const Duration(milliseconds: 1));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
        }
        // Accepted work keeps its live progress animation running. Render the
        // completed editor transition without waiting for that turn to finish.
        expect(original.runtime.changingAnswer, isFalse);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          host.calls
              .singleWhere((call) => call.$1 == 'prompt.submit')
              .$2['text'],
          'Retained correction',
        );
        if (rejected) {
          expect(
            find.descendant(
              of: field,
              matching: find.text('Retained correction'),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('edit-message-error')),
            findsOneWidget,
          );
          expect(tester.widget<TextFormField>(field).enabled, isTrue);
        } else {
          expect(find.text('Edit message'), findsNothing);
        }
      },
    );
  }

  testWidgets('idle composer offers one-shot fork at the saved boundary', (
    tester,
  ) async {
    await controller.updateDraft(original, 'Composer followup');
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Send')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('composer-choice-fork')), findsOneWidget);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('composer-choice-fork'))),
    );
    await tester.pump();
    expect(find.text('Fork'), findsOneWidget);
    expect(host.calls.where((call) => call.$1 == 'session.branch'), isEmpty);
    await gesture.up();
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 100 && original.composer.observation.text.isNotEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(
      host.calls.where((call) => call.$1 == 'session.branch'),
      hasLength(1),
    );
    expect(
      host.calls.where((call) => call.$1 == 'prompt.submit'),
      hasLength(1),
    );
    expect(original.composer.observation.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
