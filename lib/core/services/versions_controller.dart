import 'package:flutter/foundation.dart';

import '../models/connection.dart';
import '../models/hermes_profile.dart';
import 'backend_update_controller.dart';
import 'profile_gateway.dart';

typedef VersionsControllerFactory =
    VersionsController Function(SavedConnection? connection);

/// Installed version and updates for one captured server connection.
class VersionsController extends ChangeNotifier {
  VersionsController({ProfileGateway? gateway})
    : server = gateway == null ? null : BackendUpdateController(gateway) {
    server?.addListener(notifyListeners);
  }

  factory VersionsController.forConnection(SavedConnection? connection) =>
      VersionsController(
        gateway: connection == null
            ? null
            : ProfileGateway.forConnection(
                connection,
                WorkspaceScope(
                  connectionId: connection.id,
                  profileName: 'default',
                ),
              ),
      );

  final BackendUpdateController? server;
  Future<void> refresh() async {
    await server?.checkForUpdate();
  }

  @override
  void dispose() {
    server?.removeListener(notifyListeners);
    server?.dispose();
    server?.gateway.close();
    super.dispose();
  }
}
