/// Manual Android verification of the shipped profile screen with isolated data.
/// Debug entry point only. Never install this fixture as Wing.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import '../test/support/profile_intelligence_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final fixture = ProfileIntelligenceFixture();
  final controller = ProfileWorkspaceController(
    connection: SavedConnection(
      id: 'intelligence-device-qa',
      label: 'Picker verification',
      host: '127.0.0.1',
      port: 1,
      apiKey: '',
    ),
    connectionIdentity: 'intelligence-device-qa',
    preferences: await SharedPreferences.getInstance(),
    gatewayFactory: fixture.gateway,
  );
  await controller.initialize();
  await controller.createChat();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: hermesTheme(Brightness.light),
      darkTheme: hermesTheme(Brightness.dark),
      home: ProfileWorkspaceScreen(controller: controller),
    ),
  );
}
