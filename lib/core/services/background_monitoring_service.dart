import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'turn_notification_service.dart';

enum BackgroundMonitoringState {
  unsupported,
  disabled,
  noConnections,
  permissionRequired,
  waitingForApp,
  active,
  batteryRestricted,
  failed,
}

/// Android retains the same Flutter engine and its authenticated event clients.
/// Serializing reconciliation prevents a slow start from undoing a later stop.
class BackgroundMonitoringService {
  static const channel = MethodChannel(
    'com.tarkilhk.wing/background_monitoring',
  );
  final SharedPreferences preferences;
  final Future<bool> Function() hasConnections;
  final Future<bool?> Function() notificationsEnabled;
  final bool supported;
  final state = ValueNotifier(BackgroundMonitoringState.disabled);
  Future<void> _tail = Future.value();
  bool _disposed = false;

  BackgroundMonitoringService({
    required this.preferences,
    required this.hasConnections,
    required this.notificationsEnabled,
    bool? supported,
  }) : supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  Future<void> sync() {
    _tail = _tail.then((_) => _sync());
    return _tail;
  }

  Future<void> _sync() async {
    if (_disposed) return;
    if (!supported) {
      state.value = BackgroundMonitoringState.unsupported;
      return;
    }
    try {
      final enabled =
          (preferences.getBool(completionNotificationsKey) ?? true) ||
          (preferences.getBool(attentionNotificationsKey) ?? true);
      final connections = await hasConnections();
      final allowed = await notificationsEnabled() != false;
      if (_disposed) return;
      if (!enabled || !connections || !allowed) {
        await channel.invokeMethod<void>('stop');
        if (_disposed) return;
        state.value = !enabled
            ? BackgroundMonitoringState.disabled
            : !connections
            ? BackgroundMonitoringState.noConnections
            : BackgroundMonitoringState.permissionRequired;
        return;
      }
      final result = await channel.invokeMapMethod<String, dynamic>('start');
      if (_disposed) return;
      state.value = result?['running'] != true
          ? BackgroundMonitoringState.waitingForApp
          : result?['batteryUnrestricted'] == true
          ? BackgroundMonitoringState.active
          : BackgroundMonitoringState.batteryRestricted;
    } catch (_) {
      if (!_disposed) state.value = BackgroundMonitoringState.failed;
    }
  }

  Future<void> openBatterySettings() async {
    if (supported) await channel.invokeMethod<void>('openBatterySettings');
  }

  void dispose() {
    _disposed = true;
    if (supported) {
      unawaited(
        _tail.then((_) async {
          try {
            await channel.invokeMethod<void>('stop');
          } catch (_) {
            // Engine teardown can remove the platform channel first.
          }
        }),
      );
    }
    state.dispose();
  }
}
