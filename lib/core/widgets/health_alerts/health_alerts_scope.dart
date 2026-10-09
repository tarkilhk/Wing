import 'package:flutter/widgets.dart';
import '../../models/health_alert.dart';
import '../../services/health_alerts_coordinator.dart';

/// Captured app dependencies available to every route, including nested viewers.
class HealthAlertsScope extends InheritedWidget {
  const HealthAlertsScope({
    super.key,
    required this.alerts,
    required this.openHealth,
    required super.child,
  });
  final HealthAlertsCoordinator alerts;
  final Future<void> Function(HealthAlert) openHealth;
  static HealthAlertsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HealthAlertsScope>();
  @override
  bool updateShouldNotify(HealthAlertsScope oldWidget) =>
      oldWidget.alerts != alerts || oldWidget.openHealth != openHealth;
}
