import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';

import '../test/support/profile_actions_fixture.dart';

/// Manual Android gesture/keyboard checks; every transport is an in-memory fake.
class _NativeQueueFixture extends ProfileActionsFixture {
  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    {'id': 1, 'role': 'user', 'content': 'Check the queued message editor.'},
    {
      'id': 2,
      'role': 'assistant',
      'content': 'I am reviewing the conversation UI.',
    },
  ];

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: base.read,
      rpc: (method, params) async {
        if (method == 'session.steer') return {'status': 'queued'};
        return base.call(method, params);
      },
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final fixture = _NativeQueueFixture();
  final controller = ProfileWorkspaceController(
    connection: SavedConnection(
      id: 'native-queue-qa',
      label: 'Queue device QA',
      host: 'unused',
      port: 1,
      apiKey: '',
    ),
    connectionIdentity: 'isolated-native-queue-qa',
    preferences: await SharedPreferences.getInstance(),
    gatewayFactory: fixture.gateway,
  );
  await controller.initialize();
  final chat = await controller.createChat();
  chat.messages.addAll(
    fixture.historyRows(chat.key.workspace.profileName, chat.key.sessionId),
  );
  chat.title = 'Queued message device check';
  chat.status = ProfileTurnStatus.running;
  await controller.queuePrompt(chat, 'Review the layout');
  await controller.queuePrompt(chat, 'Then check the tests');
  await controller.updateDraft(
    chat,
    'My unfinished draft\nKeep this second line.',
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: wingTheme(Brightness.dark),
      home: ProfileWorkspaceScreen(controller: controller),
    ),
  );
}
