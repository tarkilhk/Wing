import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import '../../services/connection_manager.dart';
import '../../services/server_connection_status.dart';
import 'admin_tool_setup_page.dart';
import '../../widgets/server_connection_label.dart';

/// Single integration point for App settings. Capture the owner before routing;
/// an administration navigation redesign only needs to change this entry point.
Future<void> openProfileVoiceSettings(
  BuildContext context, {
  required SavedConnection connection,
  required String connectionIdentity,
  required ServerConnectionStatus connectionStatus,
  required String profileName,
}) async {
  final repository = AdministrationRepository.forConnection(
    connection,
    connectionIdentity,
    connectionStatus: connectionStatus,
  );
  try {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ServerConnectionScope(
          status: connectionStatus,
          child: AdminToolSetupPage(
            profile: repository.profile(profileName),
            name: 'tts',
          ),
        ),
      ),
    );
  } finally {
    repository.close();
  }
}
