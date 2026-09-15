/// Native lifecycle fixture. Run with tools/qa/check_background_monitoring.py.
/// Uses production controllers, notification posting and the retained Android
/// engine; only Hermes transport responses are fixtures. No model calls.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_connection_identity.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profile_workspace_registry.dart';
import 'package:wing/core/services/turn_notification_service.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/main.dart';

import '../test/profile_connection_identity_test.dart' show MemoryIdentityStore;
import '../test/profile_notification_coverage_test.dart'
    show NotificationCoverageHost;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final secrets = MemoryIdentityStore();
  final manager = ConnectionManager(preferences, credentialStore: secrets);
  final connection = SavedConnection(
    id: 'monitoring-native-fixture',
    label: 'Monitoring fixture',
    host: '127.0.0.1',
    port: 1,
    apiKey: '',
  );
  await manager.importConnections([connection], replaceExisting: true);
  await preferences.setString('last_connection_id', connection.id);
  await preferences.setBool(completionNotificationsKey, true);
  await preferences.setBool(attentionNotificationsKey, true);
  final host = NotificationCoverageHost();
  final app = GlobalKey<WingAppState>();
  final sink = PluginTurnNotificationSink(
    onOpen: (payload) {
      app.currentState?.openProfileNotification(payload);
    },
  );
  await sink.initialize();
  var alerts = 0;
  final generation = DateTime.now().microsecondsSinceEpoch.toString();
  final registry = ProfileWorkspaceRegistry(
    identities: ProfileConnectionIdentity(credentialStore: secrets),
    create: (saved, identity) => ProfileWorkspaceController(
      connection: saved,
      connectionIdentity: identity,
      preferences: preferences,
      gatewayFactory: host.gateway,
      onAttention: (chat) async {
        final id = 240001 + alerts;
        await sink.show(
          TurnNotification(
            id: id,
            title: chat.title,
            body: chat.content.body(showPreview: true),
            expandedBody: chat.content.body(showPreview: true, limit: 800),
            scopeLabel:
                '${chat.connectionLabel} / ${chat.key.workspace.profileName}',
            payload: jsonEncode(chat.key.toJson()),
            channel: TurnNotificationService.turnChannel,
          ),
        );
        alerts++;
      },
    ),
  );
  final controller = await registry.forConnection(connection);
  await controller.initialize();
  final chats = <String, ProfileChat>{};
  for (final profile in ['a', 'b']) {
    await controller.switchProfile(profile);
    chats[profile] = await controller.createChat()
      ..title = profile == 'a' ? 'First task' : 'Second task';
  }
  await controller.switchProfile('a');
  runApp(WingApp(key: app, connManager: manager, profileControllers: registry));
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18765);
  await for (final request in server) {
    try {
      if (request.method == 'POST' && request.uri.path == '/event') {
        final event =
            jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final profile = event['profile'] as String;
        final chat = chats[profile]!;
        final state = event['state'] as String;
        host.workingProfiles.remove(profile);
        host.waitingProfiles.remove(profile);
        if (state == 'working') host.workingProfiles.add(profile);
        if (state == 'waiting') host.waitingProfiles.add(profile);
        if (state == 'working') {
          if (chat.pendingQuestion != null) {
            await controller.clarify(chat, 'Continue');
          } else {
            chat.draft = 'Native fixture work';
            await controller.send(chat);
          }
        } else {
          host.gateways[profile]!.onEvent!(
            StreamEvent(
              type: state == 'waiting' ? 'clarify' : 'message.complete',
              sessionId: chat.runtimeId,
              data: state == 'waiting'
                  ? {'request_id': 'question-$profile', 'question': 'Continue?'}
                  : {
                      'text':
                          '**Reply ready.** ${'More readable context. ' * 20}',
                    },
            ),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (request.method == 'POST' && request.uri.path == '/close-activity') {
        await SystemNavigator.pop();
      }
      if (request.method == 'POST' && request.uri.path == '/alerts') {
        final enabled =
            jsonDecode(await utf8.decoder.bind(request).join()) as bool;
        await preferences.setBool(completionNotificationsKey, enabled);
        await preferences.setBool(attentionNotificationsKey, enabled);
        app.currentState!.refreshPreferences();
      }
      await preferences.reload();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'generation': generation,
          'ready': host.gateways.containsKey('a'),
          'alerts': alerts,
          'active': registry.hasActiveChats,
          'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
          'enabled':
              (preferences.getBool(completionNotificationsKey) ?? true) ||
              (preferences.getBool(attentionNotificationsKey) ?? true),
        }),
      );
    } catch (_) {
      request.response.statusCode = 500;
    } finally {
      await request.response.close();
    }
  }
}
