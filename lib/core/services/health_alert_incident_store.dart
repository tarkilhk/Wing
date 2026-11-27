import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../models/health_alert.dart';

/// Device-owned unresolved incidents, isolated by exact connection identity.
/// Writes survive route/session disposal and serialize across replacement owners.
class HealthAlertIncidentStore {
  HealthAlertIncidentStore(this.preferences);
  final SharedPreferences preferences;
  static const _prefix = 'wing-health-alert-incidents:';
  final _writes = <String, Future<void>>{};
  final _removals = <String, Future<void>>{};
  String _key(String connection) =>
      '$_prefix${Uri.encodeComponent(connection)}';

  List<HealthAlert> read(String connection) {
    final key = _key(connection);
    if (_removals.containsKey(key)) return const [];
    final raw = preferences.getString(key);
    if (raw == null) return const [];
    final alerts = (jsonDecode(raw) as List)
        .map((value) => _decode(value as Map))
        .toList();
    if (alerts.any((alert) => alert.connectionIdentity != connection)) {
      throw const FormatException('Incident connection does not match');
    }
    return alerts;
  }

  Future<void> write(String connection, List<HealthAlert> alerts) {
    // Capture before queuing, so later evaluator changes cannot alter this write.
    final raw = jsonEncode(alerts.map(_encode).toList());
    final key = _key(connection);
    return _enqueue(key, () => preferences.setString(key, raw));
  }

  /// Include queued writes even when the first incident has not reached disk.
  Future<void> retainConnections(Set<String> connections) {
    final keep = connections.map(_key).toSet();
    final obsolete = {
      ...preferences.getKeys().where((key) => key.startsWith(_prefix)),
      ..._writes.keys,
    }.difference(keep);
    return Future.wait([
      for (final key in obsolete)
        _enqueue(key, () => preferences.remove(key), removing: true),
    ]);
  }

  Future<void> _enqueue(
    String key,
    Future<bool> Function() persist, {
    bool removing = false,
  }) {
    final previous = _writes[key] ?? Future<void>.value();
    late final Future<void> write;
    write = previous
        .catchError((Object _) {})
        .then((_) async {
          if (!await persist()) {
            throw StateError('Health alert incidents were not saved');
          }
        })
        .whenComplete(() {
          if (identical(_writes[key], write)) _writes.remove(key);
          if (identical(_removals[key], write)) _removals.remove(key);
        });
    _writes[key] = write;
    if (removing) _removals[key] = write;
    return write;
  }

  Map<String, Object?> _encode(HealthAlert alert) => {
    'id': alert.id,
    'connectionIdentity': alert.connectionIdentity,
    'connectionLabel': alert.connectionLabel,
    'scope': alert.scope.name,
    'title': alert.title,
    'detail': alert.detail,
    'severity': alert.severity.name,
    'observedAt': alert.observedAt.toUtc().toIso8601String(),
    'occurrence': alert.occurrence,
    'destination': alert.destination,
    'connectorNames': alert.connectorNames,
    'profileName': alert.profileName,
    'trigger': alert.trigger == null
        ? null
        : {
            'usedPercent': alert.trigger!.usedPercent,
            'warningAbovePercent': alert.trigger!.warningAbovePercent,
            'alertMinutes': alert.trigger!.alertMinutes,
            'criticalPressure': alert.trigger!.criticalPressure,
          },
    'acknowledged': alert.acknowledged,
    'snoozedUntil': alert.snoozedUntil?.toUtc().toIso8601String(),
  };

  HealthAlert _decode(Map value) {
    final trigger = value['trigger'] as Map?;
    return HealthAlert(
      id: value['id'] as String,
      connectionIdentity: value['connectionIdentity'] as String,
      connectionLabel: value['connectionLabel'] as String,
      scope: HealthAlertScope.values.byName(value['scope'] as String),
      title: value['title'] as String,
      detail: value['detail'] as String,
      severity: HealthAlertSeverity.values.byName(value['severity'] as String),
      observedAt: DateTime.parse(value['observedAt'] as String),
      occurrence: value['occurrence'] as int,
      destination: value['destination'] as String?,
      connectorNames: List.unmodifiable(
        List<String>.from(value['connectorNames'] as List),
      ),
      profileName: value['profileName'] as String?,
      trigger: trigger == null
          ? null
          : HealthAlertTrigger(
              usedPercent: (trigger['usedPercent'] as num?)?.toDouble(),
              warningAbovePercent: (trigger['warningAbovePercent'] as num)
                  .toDouble(),
              alertMinutes: trigger['alertMinutes'] as int,
              criticalPressure: trigger['criticalPressure'] as bool,
            ),
      acknowledged: value['acknowledged'] as bool,
      snoozedUntil: value['snoozedUntil'] == null
          ? null
          : DateTime.parse(value['snoozedUntil'] as String),
      lastKnown: true,
    );
  }
}
