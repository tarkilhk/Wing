/// Authored UI preview only. This target never connects to Hermes and is never
/// imported by lib/main.dart. Restore the normal APK after visual inspection.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import '../test/support/profile_actions_fixture.dart';

class DesignPreviewFixture extends ProfileActionsFixture {
  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    {
      'id': 1,
      'role': 'user',
      'content': 'How should we improve the workspace?',
    },
    {
      'id': 2,
      'role': 'tool',
      'tool_name': 'Read project',
      'content': 'Read-only inspection of the authored preview project.',
    },
    {
      'id': 3,
      'role': 'tool',
      'tool_name': 'Compare layouts',
      'content': 'Compare long titles and small-screen layouts.',
    },
    {
      'id': 4,
      'role': 'tool',
      'tool_name': 'Check accessibility',
      'content':
          'Check contrast and large text. This is preview data, not a test result.',
    },
    {
      'id': 5,
      'role': 'assistant',
      'content':
          '## Give the work more room\n\nKeep **answers in focus** and execution details one tap away.\n\n- Compact menus stay beside their chat.\n- Your accent follows you into the conversation.\n- Questions and approvals remain visible.\n\n```dart\nfinal scope = selectedProfile;\nawait gateway.sessions(profile: scope);\n```\n\nAuthored design preview. No gateway is connected.',
    },
  ];
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('Design preview: starting');
  final fixture = DesignPreviewFixture();
  final controller = ProfileWorkspaceController(
    connection: SavedConnection(
      id: 'ui-preview',
      label: 'UI preview · Prestige',
      host: 'unused',
      port: 1,
      apiKey: '',
    ),
    connectionIdentity: 'authored-ui-preview',
    preferences: await SharedPreferences.getInstance(),
    gatewayFactory: fixture.gateway,
  );
  await controller.initialize();
  debugPrint('Design preview: initialized');
  for (final (id, status) in [
    ('pinned', ProfileTurnStatus.completed),
    ('newest', ProfileTurnStatus.running),
    ('pin-two', ProfileTurnStatus.attention),
  ]) {
    final row = controller.current!.sessions.firstWhere(
      (row) => row['id'] == id,
    );
    controller.current!.chats[id] = ProfileChat(
      key: ProfileSessionKey(controller.current!.scope, id),
      runtimeId: 'preview-$id',
      title: row['title'] as String,
    )..status = status;
  }
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: wingTheme(Brightness.light),
      darkTheme: wingTheme(Brightness.dark),
      home: ProfileWorkspaceScreen(controller: controller),
    ),
  );
}
