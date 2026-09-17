import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/connection.dart';
import '../models/hermes_profile.dart';
import 'backend_update_controller.dart';
import 'profile_gateway.dart';

typedef VersionsControllerFactory =
    VersionsController Function(SavedConnection? connection);

/// Installed client identity and updates for one captured server connection.
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
  String? clientVersion;
  bool clientLoading = true;
  bool _disposed = false;

  Future<void> _loadClientVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!_disposed) clientVersion = info.version;
    } catch (_) {
      // Installed metadata can be unavailable; no remote client check is made.
    } finally {
      if (!_disposed) {
        clientLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() => Future.wait([
    _loadClientVersion(),
    if (server != null) server!.checkForUpdate(),
  ]);

  @override
  void dispose() {
    _disposed = true;
    server?.removeListener(notifyListeners);
    server?.dispose();
    server?.gateway.close();
    super.dispose();
  }
}
