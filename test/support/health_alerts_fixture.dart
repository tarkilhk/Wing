import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_connection_identity.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profile_workspace_registry.dart';
import 'package:wing/core/services/background_monitoring_service.dart';
import 'package:wing/core/services/health_alert_settings_session.dart';
import 'package:wing/core/services/health_alert_settings_store.dart';
import 'package:wing/core/services/health_alerts_coordinator.dart';
import 'host_resources_fixture.dart';

class AlertWorkspaceFixture extends ProfileWorkspaceController {
  AlertWorkspaceFixture(SharedPreferences prefs, AppPreferences preferences)
    : super(
        access: ConnectionAccess(
          connection: SavedConnection(
            id: 'server',
            label: 'Home server',
            host: 'localhost',
            port: 1,
            apiKey: '',
          ),
          dashboardOAuth: null,
        ),
        connectionIdentity: 'endpoint',
        preferences: prefs,
        appPreferences: preferences,
      );
  bool mountedRoute = true, working = false;
  @override
  bool get initialized => true;
  @override
  bool get hasMountedRoutes => mountedRoute;
  @override
  bool get hasActiveChats => working;
  void publishActivity() => notifyListeners();
}

class AlertRegistryFixture extends ProfileWorkspaceRegistry {
  AlertRegistryFixture(this.workspace)
    : super(
        identities: ProfileConnectionIdentity(),
        create: (_, _) => throw StateError('unused'),
      );
  final AlertWorkspaceFixture workspace;
  @override
  Iterable<ProfileWorkspaceController> get controllers => [workspace];
}

class HealthAlertsFixture {
  HealthAlertsFixture(this.preferences) {
    appPreferences = AppPreferences(preferences);
    owner = AlertWorkspaceFixture(preferences, appPreferences);
    owner.hostResources(repository: host.server);
    registry = AlertRegistryFixture(owner);
    settings = HealthAlertSettingsSession(
      HealthAlertSettingsStore(preferences),
    );
    coordinator = HealthAlertsCoordinator(
      registry: registry,
      settings: settings,
      monitoring: monitoring,
    );
  }
  final SharedPreferences preferences;
  final host = HostResourcesFixture();
  final monitoring = ValueNotifier(BackgroundMonitoringState.idle);
  late final AppPreferences appPreferences;
  late final AlertWorkspaceFixture owner;
  late final AlertRegistryFixture registry;
  late final HealthAlertSettingsSession settings;
  late final HealthAlertsCoordinator coordinator;
  Future<void> critical() async {
    host.pressure = hostPressurePayload();
    host.pressure['memory']['pressure'] = 'critical';
    await owner.hostResources().refresh();
  }

  void dispose() {
    coordinator.dispose();
    settings.dispose();
    registry.dispose();
    owner.dispose();
    host.server.close();
    monitoring.dispose();
    appPreferences.dispose();
  }
}
