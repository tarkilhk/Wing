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
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/main.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;
import 'support/recording_turn_notification_sink.dart';

void main() {
  testWidgets(
    'restored notice tap from chat list clears read state across restart',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        'notification_permission_requested': true,
        'microphone_permission_requested': true,
      });
      final preferences = await SharedPreferences.getInstance();
      final manager = await ConnectionManager.create(preferences);
      final connection = identityTestConnection();
      await manager.importConnections([connection], replaceExisting: true);
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
      final seed = ChatNotificationCoordinator(preferences, seedSink);
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
      const plugin = MethodChannel('dexterous.com/flutter/local_notifications');
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
      messenger.setMockMethodCallHandler(NativeNotificationSink.channel, (
        call,
      ) async {
        if (call.method == 'show') shown.add(call.arguments as Map);
        if (call.method == 'cancel') cancelled.add(call.arguments as int);
        return call.method == 'initialize' ? [] : null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(plugin, null);
        messenger.setMockMethodCallHandler(
          NativeNotificationSink.channel,
          null,
        );
      });
      final host = Host()
        ..running = false
        ..historyMessages = [
          {'id': 1, 'role': 'user', 'content': 'Prepare the result'},
          {'id': 2, 'role': 'assistant', 'content': answer},
        ];
      final app = GlobalKey<WingAppState>();
      await tester.pumpWidget(
        WingApp(
          key: app,
          connManager: manager,
          gatewayFactory: (_, scope) => host.gateway(scope),
        ),
      );
      await tester.pumpAndSettle();
      expect(shown, hasLength(1));
      expect(shown.single['alert'], isFalse);
      expect(cancelled, isEmpty);
      await tester.tap(find.text('Host').first);
      await tester.pumpAndSettle();
      // Exercise the native interaction entry point and production-created
      // controller callbacks, not a coordinator.read or app routing test double.
      final tap = messenger.handlePlatformMessage(
        NativeNotificationSink.channel.name,
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
      final controller = await app.currentState!.profileController(connection);
      final chat = controller.current!.chat!;
      final scroll = find
          .descendant(
            of: find.byType(ProfileTranscript),
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(scroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text(answer), findsWidgets);
      expect(chat.historyError, isNull);
      expect(chat.offlineSnapshot, isFalse);
      expect(cancelled, contains(seedSink.shown.single.id));
      expect(controller.visible, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      shown.clear();
      cancelled.clear();
      await tester.pumpWidget(
        WingApp(
          connManager: manager,
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
