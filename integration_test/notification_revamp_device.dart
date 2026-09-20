/// Isolated native QA entry point. Build with -PnotificationQa=true; never
/// install this fixture under the production package. Hermes is entirely fake.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/turn_notification_service.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/main.dart';
import '../test/profile_connection_identity_test.dart' show MemoryIdentityStore;
import '../test/profile_workspace_controller_test.dart' show Host;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final manager = ConnectionManager(
    prefs,
    credentialStore: MemoryIdentityStore(),
  );
  final connection = SavedConnection(
    id: 'notification-qa',
    label: 'Home server',
    host: '127.0.0.1',
    port: 1,
    apiKey: '',
  );
  await manager.importConnections([connection], replaceExisting: true);
  await prefs.setBool(completionNotificationsKey, true);
  await prefs.setBool(attentionNotificationsKey, true);
  await prefs.setBool('notification_permission_requested', true);
  await prefs.setBool('microphone_permission_requested', true);
  final host = Host()
    ..running = false
    ..pendingApprovals = [];
  final app = GlobalKey<WingAppState>();
  runApp(
    WingApp(
      key: app,
      connManager: manager,
      gatewayFactory: (_, scope) => host.gateway(scope),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  final controller = await app.currentState!.profileController(connection);
  await controller.initialize();
  await controller.switchProfile('a');
  final chat = await controller.createChat()
    ..title = 'Website refresh';
  await controller.switchProfile('b');
  final other = await controller.createChat()
    ..title = 'Weekly report';
  void event(ProfileChat target, String type, Map<String, dynamic> data) {
    host.gateways[target.key.workspace.profileName]!.onEvent!(
      StreamEvent(type: type, sessionId: target.runtimeId, data: data),
    );
  }

  var sequence = 0;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18766);
  await for (final request in server) {
    try {
      final data = request.method == 'POST'
          ? jsonDecode(await utf8.decoder.bind(request).join()) as Map
          : const {};
      switch (request.uri.path) {
        case '/work':
          other.draft = 'Prepare the weekly report';
          await controller.send(other);
        case '/approval':
          final id = 'qa-${++sequence}';
          final approval = <String, dynamic>{
            'request_id': id,
            'command': data['command'] ?? 'npm run deploy',
            'description': 'Publish the website preview',
            'choices': data['choices'] ?? ['once', 'session', 'always', 'deny'],
          };
          host.pendingApprovals!.add(approval);
          event(chat, 'approval', approval);
        case '/question':
          final count = (data['count'] as num?)?.toInt() ?? 3;
          event(chat, 'clarify', {
            'request_id': 'qa-question-count',
            'questions': [
              for (var index = 0; index < count; index++)
                {
                  'qid': 'q$index',
                  'question': 'Which sample output should I prepare?',
                  'choices': ['Summary', 'Checklist'],
                },
            ],
          });
        case '/reply':
          if (!chat.busy) {
            chat.draft = 'Update the website';
            await controller.send(chat);
          }
          final answer =
              data['text'] as String? ??
              'The updated website is ready. Review the new mobile layout before publishing.';
          host.historyMessages = [
            {'id': ++sequence, 'role': 'assistant', 'content': answer},
          ];
          event(chat, 'message.complete', {'text': answer});
        case '/error':
          event(chat, 'turn.error', {
            'message':
                'The provider is unavailable. Review the chat before retrying.',
          });
        case '/fail':
          host.approvalFails = data['enabled'] == true;
        case '/remote':
          host.pendingApprovals!.clear();
          host.notificationActiveSessions = [
            {'id': chat.runtimeId, 'session_key': chat.key.sessionId},
          ];
          host.notificationReplay = {
            'open_requests': [],
            'events': [],
            'latest_seq': 0,
            'truncated': false,
          };
        case '/preview':
          await prefs.setBool(notificationPreviewsKey, data['enabled'] == true);
          app.currentState!.refreshPreferences();
        case '/stop':
          event(other, 'message.complete', {
            'text': 'The weekly report is ready to read.',
          });
        case '/open':
          await app.currentState!.openProfileNotification(
            jsonEncode(chat.key.toJson()),
          );
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'ready': true,
          'runtime': chat.runtimeId,
          'pending': host.pendingApprovals,
          'decisions': host.calls
              .where(
                (c) => c.$2 == 'approval.respond' || c.$2 == 'request.answer',
              )
              .map((c) => {'method': c.$2, 'params': c.$3})
              .toList(),
          'notices': prefs.getString('chat_notification_state'),
          'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
        }),
      );
    } catch (error, stack) {
      request.response.statusCode = 500;
      request.response.write('$error\n$stack');
    } finally {
      await request.response.close();
    }
  }
}
