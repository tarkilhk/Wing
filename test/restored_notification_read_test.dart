import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/chat_notification_content.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/notification_focus.dart';
import 'package:wing/core/screens/profile_transcript.dart';
import 'package:wing/core/services/chat_notification_coordinator.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/native_notification_sink.dart';
import 'package:wing/core/services/profile_connection_identity.dart';
import 'package:wing/main.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;
import 'support/recording_turn_notification_sink.dart';
import 'helpers/pump_markdown_widget.dart';

const _nativeNotifications = MethodChannel(NativeNotificationSink.channelName);

void main() {
  for (final savedOffset in [0.0, 1000.0]) {
    testWidgets(
      'restored notice tap overrides saved offset $savedOffset and clears read state across restart',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({
          'notification_permission_requested': true,
          'microphone_permission_requested': true,
        });
        final preferences = await SharedPreferences.getInstance();
        final appPreferences = AppPreferences(preferences);
        addTearDown(appPreferences.dispose);
        final manager = await ConnectionManager.create(preferences);
        final connection = identityTestConnection();
        await manager.importConnections(
          [connection],
          replaceExisting: true,
          canCommit: () => true,
        );
        final identity = await ProfileConnectionIdentity().resolve(connection);
        final key = ProfileSessionKey(
          WorkspaceScope(
            connectionId: connection.id,
            connectionIdentity: identity,
            profileName: 'a',
          ),
          'same',
        );
        final seedSink = RecordingTurnNotificationSink();
        final seed = ChatNotificationCoordinator(
          preferences,
          seedSink,
          appPreferences: appPreferences,
        );
        const answer =
            'WING-RESTORE-REPLY: The unread result is ready. Open Wing to read it.';
        await seed.result(
          chat: jsonEncode(key.toJson()),
          title: 'Notification test',
          scope: 'Host / a',
          focus: const NotificationFocus('answer', 'original-reply'),
          content: ChatNotificationContent.reply(answer),
        );
        final shown = <Map<dynamic, dynamic>>[];
        final cancelled = <int>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const plugin = MethodChannel(
          'dexterous.com/flutter/local_notifications',
        );
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        messenger.setMockMethodCallHandler(
          plugin,
          (call) async => switch (call.method) {
            'initialize' => true,
            'getNotificationAppLaunchDetails' => {
              'notificationLaunchedApp': false,
            },
            'areNotificationsEnabled' => true,
            _ => null,
          },
        );
        messenger.setMockMethodCallHandler(_nativeNotifications, (call) async {
          if (call.method == 'show') shown.add(call.arguments as Map);
          if (call.method == 'cancel') cancelled.add(call.arguments as int);
          return call.method == 'initialize' ? [] : null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(plugin, null);
          messenger.setMockMethodCallHandler(_nativeNotifications, null);
        });
        final host = Host()
          ..running = false
          ..historyMessages = [
            if (savedOffset > 0)
              for (var index = 1; index <= 30; index++)
                {
                  'id': index,
                  'role': 'user',
                  'content':
                      'Earlier question $index with enough text to fill the history.',
                },
            {'id': 100, 'role': 'user', 'content': 'Prepare the result'},
            {'id': 101, 'role': 'assistant', 'content': answer},
          ];
        final app = GlobalKey<WingAppState>();
        await tester.pumpWidget(
          WingApp(
            key: app,
            connManager: manager,
            appPreferences: appPreferences,
            gatewayFactory: (_, scope) => host.gateway(scope),
          ),
        );
        await tester.pumpAndSettle();
        expect(shown, hasLength(1));
        expect(shown.single['alert'], isFalse);
        expect(cancelled, isEmpty);
        await tester.tap(find.text('Host').first);
        await tester.pumpAndSettle();
        final controller = await app.currentState!.profileController(
          connection,
        );
        if (savedOffset > 0) {
          final previousChat = (await controller.openSession(key))!;
          previousChat.reading.recordScrollOffset(savedOffset);
          await controller.updateDraft(
            previousChat,
            'An unsent draft to preserve',
          );
          controller.showList();
          await tester.pumpAndSettle();
          expect(cancelled, isEmpty);
        }
        // Exercise the native interaction entry point and production-created
        // controller callbacks, not a coordinator.read or app routing test double.
        final tap = messenger.handlePlatformMessage(
          _nativeNotifications.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('interaction', {'payload': shown.single['payload']}),
          ),
          (_) {},
        );
        var handled = false;
        unawaited(tap.then((_) => handled = true));
        for (var frame = 0; frame < 30 && !handled; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(handled, isTrue, reason: 'native tap handling must finish');
        await tester.pumpAndSettle();
        expect(find.byType(ProfileTranscript), findsOneWidget);
        final chat = controller.current!.chat!;
        await tester.settleMarkdown();
        await tester.pumpAndSettle();
        expect(find.text(answer), findsWidgets);
        final viewport = tester.getRect(
          find.byKey(const ValueKey('profile-transcript')),
        );
        expect(
          viewport.overlaps(tester.getRect(find.text(answer).first)),
          isTrue,
        );
        if (savedOffset > 0) {
          expect(chat.reading.historyScrollOffset, lessThan(savedOffset));
          expect(chat.composer.observation.text, 'An unsent draft to preserve');
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const Key('profile-message-composer')),
                )
                .controller!
                .text,
            'An unsent draft to preserve',
          );
        }
        expect(chat.reading.historyError, isNull);
        expect(chat.runtime.offline, isFalse);
        expect(cancelled, contains(seedSink.shown.single.id));
        expect(controller.visible, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        shown.clear();
        cancelled.clear();
        final restartedPreferences = AppPreferences(preferences);
        addTearDown(restartedPreferences.dispose);
        await tester.pumpWidget(
          WingApp(
            connManager: manager,
            appPreferences: restartedPreferences,
            gatewayFactory: (_, scope) => host.gateway(scope),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          shown,
          isEmpty,
          reason: 'read acknowledgement must survive the next cold launch',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
