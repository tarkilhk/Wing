// Disposable emulator fixture: production offline App settings and real Android sharing.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/app_settings_content.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_diagnostics.dart';
import 'package:wing/core/services/diagnostic_export.dart';
import 'package:wing/core/theme/wing_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.ensureSemantics();
  initializeDiagnosticCapture();
  logConnectionDiagnostic(
    'qa.incident',
    details: {'close_code': 1006, 'pending_requests': 2},
    error: const SocketException(
      'diagnostic-secret-chat password=fixture-secret',
    ),
  );
  final preferences = AppPreferences(await SharedPreferences.getInstance());
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: wingTheme(Brightness.light),
      home: Scaffold(
        appBar: AppBar(title: const Text('App settings')),
        body: AppSettingsContent(
          preferences: preferences,
          pluginServer: null,
          createVoiceSession: () =>
              throw StateError('Voice is outside this fixture'),
          onChanged: () {},
        ),
      ),
    ),
  );
}
