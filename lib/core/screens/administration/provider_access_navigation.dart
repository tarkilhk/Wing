import 'package:flutter/material.dart';

import '../../services/administration_repository.dart';
import '../../services/connection_manager.dart';
import '../../services/server_connection_status.dart';
import '../../widgets/server_connection_label.dart';
import 'admin_providers_page.dart';

/// Opens account access for the profile captured by the calling chat.
Future<void> openProfileProviderAccess(
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
          child: AdminProvidersPage(profile: repository.profile(profileName)),
        ),
      ),
    );
  } finally {
    repository.close();
  }
}
