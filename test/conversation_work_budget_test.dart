import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/models/queued_prompt_draft.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/profile_message.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_history_fixture.dart';

void main() {
  for (final editingQueue in [false, true]) {
    testWidgets(
      'typing ${editingQueue ? 'a queue edit' : 'a draft'} does not rebuild the unchanged conversation',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final fixture = ProfileHistoryFixture()..messageCount = 20;
        final controller = ProfileWorkspaceController(
          connection: identityTestConnection(),
          connectionIdentity: 'conversation-work-budget',
          preferences: await SharedPreferences.getInstance(),
          gatewayFactory: fixture.gateway,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.openSession(
          ProfileSessionKey(controller.current!.scope, 'chat-0'),
        );
        final chat = controller.current!.chat!;
        if (editingQueue) {
          final prompt = QueuedPromptDraft(text: 'Original queued message');
          chat.queuedPrompts.add(prompt);
          await controller.beginQueuedPromptEdit(chat, prompt);
        }
        await tester.pumpWidget(
          MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
        );
        await tester.pumpAndSettle();
        final field = find.byKey(const Key('profile-message-composer'));
        await tester.enterText(field, 'Warm up');
        await tester.pumpAndSettle();
        expect(find.byType(ProfileMessage), findsWidgets);
        var messageBuilds = 0;
        var workspaceUpdates = 0;
        controller.addListener(() => workspaceUpdates++);
        final previous = debugOnRebuildDirtyWidget;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          if (element.widget is ProfileMessage) messageBuilds++;
          previous?.call(element, builtOnce);
        };
        addTearDown(() => debugOnRebuildDirtyWidget = previous);
        final watch = Stopwatch()..start();
        for (var i = 1; i <= 30; i++) {
          await tester.enterText(field, 'A draft ${'x' * i}');
          await tester.pump(const Duration(milliseconds: 16));
        }
        watch.stop();
        // Work counts are deterministic; host debug timings are diagnostic only.
        debugPrint(
          'Typing 30 edits: $messageBuilds message builds; '
          '${watch.elapsedMilliseconds} ms host debug elapsed',
        );
        expect(chat.composerText, 'A draft ${'x' * 30}');
        expect(
          workspaceUpdates,
          0,
          reason: 'Keystrokes must not wake workspace/monitoring observers.',
        );
        if (editingQueue) {
          expect(chat.queuedPrompts.single.text, 'Original queued message');
        } else {
          expect(
            controller.preferences.getString(
              'composer_drafts_v1_conversation-work-budget',
            ),
            contains(chat.draft),
          );
        }
        // Programmatic edits still reach the field through the composer listener.
        if (editingQueue) {
          controller.updateQueuedPromptEdit(chat, 'Programmatic edit');
        } else {
          await controller.updateDraft(chat, 'Programmatic edit');
        }
        await tester.pump();
        expect(
          tester.widget<TextField>(field).controller!.text,
          'Programmatic edit',
        );
        expect(
          messageBuilds,
          0,
          reason: 'Typing must not re-render unchanged chat history.',
        );
      },
    );
  }
}
