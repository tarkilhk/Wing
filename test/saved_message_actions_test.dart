import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/answer_versions.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/models/queued_prompt_draft.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'answer_versions_test.dart' show AnswerHost;

void main() {
  late AnswerHost host;
  late ProfileWorkspaceController controller;
  late ProfileChat original;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    host = AnswerHost();
    controller = ProfileWorkspaceController(
      connectionIdentity: 'host-settings',
      connection: SavedConnection(
        id: 'host',
        label: 'Host',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      preferences: preferences,
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    await controller.openSession(
      ProfileSessionKey(controller.current!.scope, 'original'),
    );
    original = controller.current!.chat!;
  });

  tearDown(() => controller.dispose());

  test('edit rewinds the addressed row and pauses queued followups', () async {
    await controller.updateDraft(original, 'Unrelated composer draft');
    original.queuedPrompts.add(QueuedPromptDraft(text: 'Queued followup'));

    final accepted = await controller.editSavedPrompt(
      original,
      original.messages.first,
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
    expect(original.draft, 'Unrelated composer draft');
    expect(original.queuedPrompts.single.text, 'Queued followup');
    expect(original.queuePaused, isTrue);
    expect(original.messages.map(answerMessageText), ['Corrected prompt']);
  });

  test('rejected edit restores history and keeps local work paused', () async {
    await controller.updateDraft(original, 'Keep this draft');
    original.queuedPrompts.add(
      QueuedPromptDraft(text: 'Keep this queued message'),
    );
    final before = List<Map<String, dynamic>>.of(original.messages);
    final statusBefore = original.status;
    host.submitError = JsonRpcError('prompt.submit', 'Session busy');

    final accepted = await controller.editSavedPrompt(
      original,
      original.messages.first,
      'Rejected correction',
    );

    expect(accepted, isFalse);
    expect(original.messages, before);
    expect(original.draft, 'Keep this draft');
    expect(original.queuedPrompts.single.text, 'Keep this queued message');
    expect(original.queuePaused, isTrue);
    expect(original.status, statusBefore);
  });

  test('lost edit acknowledgement is not reported as success', () async {
    await controller.updateDraft(original, 'Keep this unrelated draft');
    host.submitError = TimeoutException('connection lost');

    final accepted = await controller.editSavedPrompt(
      original,
      original.messages.first,
      'Possibly delivered correction',
    );

    expect(accepted, isFalse);
    expect(original.status, ProfileTurnStatus.reconnecting);
    expect(original.draft, 'Keep this unrelated draft');
    expect(original.error, contains('uncertain'));
  });

  test('fork sends once after the latest saved answer', () async {
    await controller.updateDraft(original, 'Continue in a fork');

    final child = await controller.forkPrompt(original, original.draft);

    expect(child, isNotNull);
    final forked = child!;
    expect(host.calls.lastWhere((call) => call.$1 == 'session.branch').$2, {
      'session_id': 'runtime-original',
      'profile': 'a',
      'count': 4,
    });
    expect(host.calls.lastWhere((call) => call.$1 == 'prompt.submit').$2, {
      'session_id': forked.runtimeId,
      'profile': 'a',
      'text': 'Continue in a fork',
    });
    expect(original.draft, isEmpty);
    expect(forked.status, ProfileTurnStatus.running);
  });

  test('failed fork send leaves the source draft intact', () async {
    await controller.updateDraft(original, 'Do not lose this');
    host.submitError = JsonRpcError('prompt.submit', 'Session busy');

    final child = await controller.forkPrompt(original, original.draft);

    expect(child, isNotNull);
    final forked = child!;
    expect(original.draft, 'Do not lose this');
    expect(forked.status, ProfileTurnStatus.reconnecting);
    expect(original.error, contains('Check the child chat'));
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
    await tester.tap(edit);
    await tester.pumpAndSettle();

    expect(find.text('Edit and resend?'), findsOneWidget);
    expect(
      find.text(
        "This replaces this message's turn and all later history in this chat.",
      ),
      findsOneWidget,
    );
    expect(find.text('Follow-up'), findsWidgets);
    expect(find.text('Replace and resend'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(host.calls.where((call) => call.$1 == 'prompt.submit'), isEmpty);
  });

  testWidgets('rejected edit keeps the correction in the dialog', (
    tester,
  ) async {
    host.submitError = JsonRpcError('prompt.submit', 'Session busy');
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
      for (var i = 0; i < 100 && original.changingAnswer; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    await tester.pump();

    expect(find.text('Edit and resend?'), findsOneWidget);
    expect(find.text('Corrected followup'), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-message-error')), findsOneWidget);
    expect(
      find.text('Hermes did not accept the edited message.'),
      findsOneWidget,
    );
  });

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
      for (var i = 0; i < 100 && original.draft.isNotEmpty; i++) {
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
    expect(original.draft, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
