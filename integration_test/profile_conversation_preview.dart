/// Authored UI preview only. No production connection or model calls.
/// Restore lib/main.dart after inspection.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import '../test/support/profile_browser_fixture.dart';

class ConversationPreviewFixture extends ProfileBrowserFixture {
  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    {
      'id': 1,
      'role': 'user',
      'content': 'Show me a simple profile-scoped request.',
    },
    {
      'id': 2,
      'role': 'tool',
      'tool_name': 'Read gateway contract',
      'content': 'GET /api/sessions\nprofile is required\nRead-only request',
    },
    {
      'id': 3,
      'role': 'assistant',
      'content':
          '## Keep each request in its profile\n\n'
          'Pass the **selected profile** with every request.\n\n'
          '```dart\nfinal query = {\n  \'profile\': profile.name,\n  \'limit\': \'50\',\n};\n```\n\n'
          '- Changing profiles refreshes the list.\n'
          '- Work in other profiles keeps running.\n\n'
          'This is authored UI test content, not a live response.',
    },
  ];
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final fixture = ConversationPreviewFixture();
  final controller = ProfileWorkspaceController(
    connection: SavedConnection(
      id: 'conversation-preview',
      label: 'UI preview',
      host: 'unused',
      port: 1,
      apiKey: '',
    ),
    connectionIdentity: 'authored-conversation-preview',
    preferences: await SharedPreferences.getInstance(),
    gatewayFactory: fixture.gateway,
  );
  await controller.initialize();
  await controller.openSession(
    ProfileSessionKey(controller.current!.scope, 'preview'),
  );
  controller.current!.chat!.title = 'Profile-scoped requests';
  controller.current!.chat!.status = ProfileTurnStatus.completed;
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: wingTheme(Brightness.light),
      darkTheme: wingTheme(Brightness.dark),
      home: ProfileWorkspaceScreen(controller: controller),
    ),
  );
}
