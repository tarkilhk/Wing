/// Isolated QA for an unopened chat's first structured request. This fixture
/// uses stock response shapes, including approval.pending's empty list.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/turn_notification_service.dart';
import 'package:wing/main.dart';

import '../test/profile_connection_identity_test.dart' show MemoryIdentityStore;
import '../test/profile_notification_coverage_test.dart'
    show NotificationCoverageHost, row;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final manager = ConnectionManager(
    prefs,
    credentialStore: MemoryIdentityStore(),
  );
  final connection = SavedConnection(
    id: 'cold-input-qa',
    label: 'QA host',
    host: '127.0.0.1',
    port: 1,
    apiKey: '',
  );
  await manager.importConnections([connection], replaceExisting: true);
  for (final key in [
    completionNotificationsKey,
    attentionNotificationsKey,
    notificationPreviewsKey,
    'notification_permission_requested',
    'microphone_permission_requested',
  ]) {
    await prefs.setBool(key, true);
  }
  final host = NotificationCoverageHost();
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
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18766);
  await for (final request in server) {
    await request.drain<void>();
    switch (request.uri.path) {
      case '/work':
        host.active = [row('outside-runtime', 'outside', 'working')];
        host.changed();
      case '/question':
        host.questions = [
          {
            'qid': 'env',
            'question': 'WING-COLD-QA: Environment?',
            'choices': ['Preview', 'Production'],
          },
          {
            'qid': 'color',
            'question': 'Color?',
            'choices': ['Blue', 'Green'],
          },
          {
            'qid': 'output',
            'question': 'Output?',
            'choices': ['Summary', 'Checklist'],
          },
        ];
        host.waitingProfiles.add('a');
        host.active = [row('outside-runtime', 'outside', 'waiting', 2)];
        host.changed();
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'ready': true,
        'openedChat': controller.current?.chat?.key.sessionId,
        'loaded': controller.notificationChats
            .map(
              (chat) => {
                'session': chat.key.sessionId,
                'status': chat.status.name,
                'pendingQuestion': chat.pendingQuestion != null,
              },
            )
            .toList(),
        'resumeCalls': host.resumeCalls,
        'notices': prefs.getString('chat_notification_state'),
      }),
    );
    await request.response.close();
  }
}
