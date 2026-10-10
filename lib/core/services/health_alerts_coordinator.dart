import 'package:flutter/foundation.dart';
import '../models/health_alert.dart';
import 'background_monitoring_service.dart';
import 'health_alert_settings_session.dart';
import 'health_alerts_session.dart';
import 'profile_workspace_controller.dart';
import 'profile_workspace_registry.dart';

/// Application lifetime and aggregate only. Connection sessions own incidents;
/// the existing monitoring service determines whether background work is alive.
class HealthAlertsCoordinator extends ChangeNotifier {
  HealthAlertsCoordinator({
    required this.registry,
    required this.settings,
    required this.monitoring,
  }) {
    registry.addListener(_reconcile);
    monitoring.addListener(_reconcile);
    settings.addListener(_reconcile);
    _reconcile();
  }
  final ProfileWorkspaceRegistry registry;
  final HealthAlertSettingsSession settings;
  final ValueListenable<BackgroundMonitoringState> monitoring;
  final _sessions = <ProfileWorkspaceController, HealthAlertsSession>{};
  final _listeners = <ProfileWorkspaceController, VoidCallback>{};
  bool _foreground = true, _closed = false;
  List<HealthAlert> get alerts {
    final result = _sessions.values.expand((s) => s.alerts).toList();
    result.sort((a, b) {
      final severity = b.severity.index.compareTo(a.severity.index);
      return severity != 0 ? severity : a.id.compareTo(b.id);
    });
    return List.unmodifiable(result);
  }

  void setForeground(bool value) {
    _foreground = value;
    _reconcile();
  }

  void _reconcile() {
    if (_closed) return;
    final owners = registry.controllers.toSet();
    for (final owner in _sessions.keys.toList()) {
      if (owners.contains(owner)) continue;
      owner.removeListener(_listeners.remove(owner)!);
      final session = _sessions.remove(owner)!;
      session.removeListener(_changed);
      session.dispose();
    }
    for (final owner in owners) {
      if (!owner.initialized && !_sessions.containsKey(owner)) continue;
      _sessions.putIfAbsent(owner, () {
        final session = HealthAlertsSession(
          host: owner.hostResources(),
          health: owner.healthSession().health,
          settings: settings,
        );
        void changed() => _ownerChanged(owner);
        _listeners[owner] = changed;
        owner.addListener(changed);
        session.addListener(_changed);
        return session;
      });
      _ownerChanged(owner);
    }
    _changed();
  }

  void _ownerChanged(ProfileWorkspaceController owner) {
    final background =
        monitoring.value == BackgroundMonitoringState.active ||
        monitoring.value == BackgroundMonitoringState.batteryRestricted;
    final active =
        _foreground && owner.hasMountedRoutes ||
        background && owner.hasActiveChats;
    _sessions[owner]?.setActive(active);
    // Borrow existing profile observations. Selection may perform its existing
    // initial/expired access checks; never start server doctor/audit in a watcher.
    if (active &&
        owner.current != null &&
        settings.settings.profile &&
        settings.settings.enabled &&
        owner.healthSession().health.profileName !=
            owner.current!.scope.profileName) {
      owner.healthSession().select(owner.current!.gateway);
    }
  }

  void _changed() {
    if (_closed) return;
    notifyListeners();
  }

  ProfileWorkspaceController? ownerFor(HealthAlert alert) => _sessions.keys
      .where((owner) => owner.connectionIdentity == alert.connectionIdentity)
      .firstOrNull;
  @override
  void dispose() {
    _closed = true;
    registry.removeListener(_reconcile);
    monitoring.removeListener(_reconcile);
    settings.removeListener(_reconcile);
    for (final e in _sessions.entries) {
      e.key.removeListener(_listeners[e.key]!);
      e.value.removeListener(_changed);
      e.value.dispose();
    }
    _sessions.clear();
    super.dispose();
  }
}
