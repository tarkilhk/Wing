import '../test/support/composer_fixture.dart';
import 'package:wing/core/models/chat_runtime.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/composer_action_button.dart';
import 'package:wing/core/widgets/profile_message.dart';

import '../test/support/existing_backend_login.dart';

/// OPTIONAL, MUTATING acceptance: obtain explicit approval before RUN_MODEL=true.
///
/// Uses the production controller, transport and composer against the owner's
/// default profile. Creates one uniquely titled chat and submits one short prompt
/// exactly once. Reads chat/project list metadata during ordinary initialization,
/// but opens no pre-existing chat or transcript. Login is loaded at runtime from
/// WING_HERMES_LOGIN_FILE; never put credentials in Dart defines.
///
/// Stock upstream f42f579cf8bac4918ac9599bece71618afadd846 has no per-chat
/// toolset override. tools.configure persists profile settings, so this test
/// inherits the owner's tools, context and memory. A marker-only instruction is
/// not a sandbox: provider retries, tools or backend hooks could incur additional
/// calls/side effects. This test changes no shared settings and accepts no pending
/// approvals. A stuck/uncertain chat is retained, never forcibly stopped/deleted.
///
/// Teardown deletes only the exact newly created chat, through production's
/// ownership and backend-idle guards. Deletion cannot undo billing, logs, memory
/// or any other model/backend side effects. Disabled runs make no backend calls.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  const runModel = bool.fromEnvironment('RUN_MODEL');

  testWidgets(
    'approved existing-server probe renders one streamed terminal reply',
    (tester) async {
      const url = String.fromEnvironment('WING_HERMES_URL');
      const loginFile = String.fromEnvironment('WING_HERMES_LOGIN_FILE');
      expect(url.isNotEmpty && loginFile.isNotEmpty, isTrue);
      final nonce =
          '${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}'
          '-${Random.secure().nextInt(1 << 32).toRadixString(36)}';
      final title = 'Wing emulator QA $nonce';
      final marker = 'WING_QA_OK_$nonce';
      final prompt =
          'This is a one-turn application integration check. '
          'Do not use tools, inspect files, change settings, or save memories. '
          'Reply with exactly this marker and nothing else: $marker';
      final connection = await readExistingBackendConnection(
        url: url,
        loginFile: loginFile,
        id: 'existing-chat-probe-$nonce',
      );
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      expect(
        (await appPreferences
                .admitProfileSelection(connection.id, 'default')
                .settled)
            .confirmed,
        isTrue,
      );
      addTearDown(appPreferences.dispose);
      final controller = ProfileWorkspaceController(
        appPreferences: appPreferences,
        access: ConnectionAccess(connection: connection, dashboardOAuth: null),
        connectionIdentity: connection.id,
        preferences: preferences,
      );
      ProfileChat? ownedChat;
      addTearDown(() async {
        try {
          final chat = ownedChat;
          if (chat != null) {
            final owner = controller.current;
            if (owner == null ||
                owner.scope != chat.key.workspace ||
                !identical(owner.chats[chat.key.sessionId], chat) ||
                chat.runtime.blocksTurnAdmission ||
                chat.composer.observation.sending ||
                chat.runtime.commandRunning ||
                chat.composer.observation.submissionUncertain) {
              debugPrint('Owned QA chat retained: ${chat.key.sessionId}');
            } else {
              // deleteSession also verifies exact scoped ownership and backend
              // idleness before closing the runtime and deleting its transcript.
              try {
                await controller.mutateSession(
                  chat.key,
                  delete: true,
                  canDispatch: () => true,
                );
                debugPrint('Owned QA chat deleted: ${chat.key.sessionId}');
              } catch (_) {
                debugPrint('Owned QA chat retained: ${chat.key.sessionId}');
                rethrow;
              }
            }
          }
        } finally {
          controller.dispose();
        }
      });

      await controller.initialize();
      expect(controller.initialized, isTrue);
      final owner = controller.current!;
      expect(owner.scope.profileName, 'default');
      expect(owner.chat, isNull);
      final chat = ownedChat = await controller.createChat(
        owner: owner.scope,
        canDispatch: () => true,
      );
      expect(chat.key.workspace, owner.scope);
      expect(chat.reading.messages, isEmpty);
      expect(chat.composer.observation.attachments, isEmpty);
      expect(chat.composer.observation.queue, isEmpty);
      debugPrint('Owned QA chat created: ${chat.key.sessionId} ($title)');
      // session.title is stock and supports a newly minted runtime before its
      // first prompt; no private title lookup or pre-existing chat is touched.
      final titled = await owner.gateway.call('session.title', {
        'session_id': chat.runtime.runtimeId,
        'title': title,
      });
      expect(titled['title'], title);
      emitChatEvent(controller, chat, 'session.title', {
        'session_id': chat.key.sessionId,
        'title': title,
      });

      var sawStreamedText = false;
      var sawToolActivity = false;
      void observeStream() {
        if (chat.reading.streaming.isNotEmpty) sawStreamedText = true;
        if (chat.runtime.toolActivities.isNotEmpty ||
            chat.runtime.tool != null) {
          sawToolActivity = true;
        }
      }

      controller.addListener(observeStream);
      addTearDown(() => controller.removeListener(observeStream));
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: ProfileWorkspaceScreen(controller: controller),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final composer = find.byKey(const Key('profile-message-composer'));
      expect(composer, findsOneWidget);
      await tester.enterText(composer, prompt);
      await tester.pump(const Duration(milliseconds: 300));
      expect(chat.composer.observation.text, prompt);
      // Exactly one user gesture: no send retry, queue, steer or regeneration.
      await tester.tap(find.byType(ComposerActionButton));
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        if (sawStreamedText &&
            chat.runtime.execution == ChatExecution.completed &&
            !chat.reading.historyLoading &&
            !controller.hasActiveChats) {
          break;
        }
        if (chat.runtime.execution == ChatExecution.failed ||
            chat.runtime.needsInput) {
          fail('The owned QA turn failed or needs input; it was not retried.');
        }
      }
      expect(chat.runtime.execution, ChatExecution.completed);
      expect(chat.runtime.error, isNull);
      expect(chat.reading.historyError, isNull);
      expect(chat.reading.historyUnavailable, isFalse);
      expect(chat.reading.historySessionId, chat.key.sessionId);
      expect(chat.composer.observation.submissionUncertain, isFalse);
      expect(chat.composer.observation.text, isEmpty);
      expect(chat.reading.streaming, isEmpty);
      expect(sawStreamedText, isTrue);
      expect(
        chat.reading.messages.where((row) => row['role'] == 'user'),
        hasLength(1),
      );
      final answers = chat.reading.messages
          .where((row) => row['role'] == 'assistant')
          .toList();
      expect(answers, hasLength(1));
      expect((answers.single['content'] as String).trim(), marker);
      expect(sawToolActivity, isFalse);
      final renderedAnswer = find.byWidgetPredicate(
        (widget) =>
            widget is ProfileMessage &&
            !widget.streaming &&
            widget.message.role == 'assistant' &&
            widget.message.text.trim() == marker,
      );
      expect(renderedAnswer, findsOneWidget);
      await tester.ensureVisible(renderedAnswer);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      debugPrint('Owned QA reply streamed and rendered: ${chat.key.sessionId}');
      // Remove screen subscriptions before teardown closes/deletes the runtime.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    },
    skip: !runModel,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
