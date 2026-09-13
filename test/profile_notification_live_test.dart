import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const port = int.fromEnvironment('HERMES_TEST_PORT');

  test(
    'real backgrounded controller forwards its completion event',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      final notifications = <({ProfileSessionKey key, bool needsInput})>[];
      final completion = Completer<void>();
      ProfileWorkspaceController? controller;
      ProfileChat? ownedChat;
      Object? cleanupFailure;
      try {
        final live = ProfileWorkspaceController(
          connection: SavedConnection(
            id: 'notification-event-live-qa',
            label: 'Notification event live QA',
            host: '127.0.0.1',
            port: port,
            dashboardPortOverride: port,
            apiKey: '',
          ),
          connectionIdentity: 'notification-event-live-qa',
          preferences: await SharedPreferences.getInstance(),
          onAttention: (chat, needsInput, [eventId]) async {
            notifications.add((key: chat.key, needsInput: needsInput));
            if (!completion.isCompleted) completion.complete();
          },
        );
        controller = live;
        await live.initialize();
        expect(live.error, isNull);
        expect(await live.switchProfile('android-qa-a'), isTrue);
        expect(live.current?.scope.profileName, 'android-qa-a');

        final chat = await live.createChat();
        ownedChat = chat;
        live.visible = false;
        await live.updateDraft(
          chat,
          'Reply exactly NOTIFICATION_EVENT_OK. Do not use tools or perform '
          'other work.',
        );
        await live.send(chat);

        await completion.future.timeout(const Duration(seconds: 105));
        expect(notifications, hasLength(1));
        expect(notifications.single.key, chat.key);
        expect(notifications.single.key.workspace.profileName, 'android-qa-a');
        expect(notifications.single.needsInput, isFalse);
        expect(chat.status, ProfileTurnStatus.completed);
        expect(chat.error, isNull);
      } finally {
        final chat = ownedChat;
        if (chat != null && chat.busy) {
          try {
            await controller?.stop(chat);
          } catch (error) {
            cleanupFailure = error;
          }
        }
        controller?.dispose();
        HttpOverrides.global = previousOverrides;
        if (cleanupFailure != null) {
          fail('Notification live cleanup failed: $cleanupFailure');
        }
      }
    },
    skip: port == 0,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
