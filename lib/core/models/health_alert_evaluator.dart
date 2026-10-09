import 'health_alert.dart';
import 'host_thresholds.dart';

/// Stateful hysteresis over independent fresh samples. No I/O, timers or UI.
/// Gaps over three times the applicable duration break progress. Collection
/// pauses retain progress; unknown readings retain incidents but reset progress.
class HealthAlertEvaluator {
  HealthAlertEvaluator({
    required this.connectionIdentity,
    required this.connectionLabel,
  });
  final String connectionIdentity, connectionLabel;
  final _alerts = <String, HealthAlert>{};
  final _periods = <String, _Period>{};
  int _occurrence = 0;
  List<HealthAlert> get alerts => List.unmodifiable(_alerts.values);
  void resetPeriods() => _periods.clear();
  void pause() {
    for (final entry in _alerts.entries.toList()) {
      _alerts[entry.key] = entry.value.copyWith(lastKnown: true);
    }
  }

  void clear() {
    _alerts.clear();
    resetPeriods();
  }

  void remove(String key) {
    _alerts.remove(key);
    _periods.remove(key);
  }

  String hostKey(HostMetric metric) =>
      '$connectionIdentity:host:${metric.name}';

  void host({
    required HostMetric metric,
    required HealthAlertRule rule,
    required DateTime now,
    DateTime? sampledAt,
    double? value,
    bool critical = false,
    bool pressureKnown = true,
  }) {
    final key = hostKey(metric);
    if (!rule.enabled) {
      remove(key);
      return;
    }
    if (sampledAt == null || value == null && !critical) {
      unknown(key);
      return;
    }
    final existing = _alerts[key];
    final label = switch (metric) {
      HostMetric.memoryUsedPercent => 'Memory usage',
      HostMetric.diskUsedPercent => 'Disk usage',
      _ => 'CPU usage',
    };
    final detail =
        '${value == null ? 'Usage percentage unavailable' : '${value.toStringAsFixed(0)}% used'} · warning above ${rule.warnAbove}%'
        '\n${switch (metric) {
          HostMetric.memoryUsedPercent => 'Memory pressure can interrupt Hermes processes or cause an out-of-memory failure.',
          HostMetric.diskUsedPercent => 'Low free space can prevent Hermes from saving chats or writing files.',
          _ => 'Sustained CPU usage may slow replies and tools.',
        }}';
    if (critical) {
      _periods.remove(key);
      _put(
        key,
        label == 'Memory usage'
            ? 'Critical memory pressure'
            : 'Critical disk pressure',
        detail,
        HealthAlertScope.host,
        HealthAlertSeverity.critical,
        sampledAt,
      );
      return;
    }
    if (value == null) return;
    final clearing =
        existing != null &&
        value < rule.clearBelow &&
        (existing.severity != HealthAlertSeverity.critical || pressureKnown);
    final raising = existing == null && value > rule.warnAbove;
    if (!clearing && !raising) {
      _periods.remove(key);
    } else {
      final old = _periods[key];
      final duration = Duration(
        minutes: clearing ? rule.clearMinutes : rule.alertMinutes,
      );
      if (old == null ||
          old.clearing != clearing ||
          sampledAt.isBefore(old.last) ||
          sampledAt.difference(old.last) > duration * 3) {
        _periods[key] = _Period(sampledAt, sampledAt, clearing);
      } else {
        old.last = sampledAt;
        if (sampledAt.difference(old.start) >= duration) {
          if (clearing) {
            remove(key);
            return;
          }
          _put(
            key,
            'High ${label.toLowerCase()}',
            detail,
            HealthAlertScope.host,
            HealthAlertSeverity.warning,
            sampledAt,
          );
          _periods.remove(key);
        }
      }
    }
    if (_alerts[key] case final alert?) {
      _alerts[key] = HealthAlert(
        id: key,
        connectionIdentity: connectionIdentity,
        connectionLabel: connectionLabel,
        scope: alert.scope,
        title: alert.title,
        detail: detail,
        severity: alert.severity,
        observedAt: sampledAt,
        occurrence: alert.occurrence,
        acknowledged: alert.acknowledged,
        snoozedUntil: alert.snoozedUntil,
        lastKnown:
            alert.severity == HealthAlertSeverity.critical && !pressureKnown,
      );
    }
  }

  void finding({
    required String key,
    required String title,
    required String detail,
    required HealthAlertScope scope,
    required DateTime? at,
    required bool? failed,
    HealthAlertSeverity severity = HealthAlertSeverity.warning,
    String? profileName,
  }) {
    if (failed == null || at == null) {
      unknown(key);
      return;
    }
    if (!failed) {
      remove(key);
      return;
    }
    _put(key, title, detail, scope, severity, at, profileName: profileName);
  }

  void unknown(String key) {
    _periods.remove(key);
    if (_alerts[key] case final alert?) {
      _alerts[key] = alert.copyWith(lastKnown: true);
    }
  }

  void _put(
    String key,
    String title,
    String detail,
    HealthAlertScope scope,
    HealthAlertSeverity severity,
    DateTime at, {
    String? profileName,
  }) {
    final old = _alerts[key];
    final escalated = old == null || severity.index > old.severity.index;
    _alerts[key] = HealthAlert(
      id: key,
      connectionIdentity: connectionIdentity,
      connectionLabel: connectionLabel,
      scope: scope,
      title: title,
      detail: detail,
      severity: severity,
      observedAt: at,
      profileName: profileName,
      occurrence: escalated ? ++_occurrence : old.occurrence,
      acknowledged: !escalated && old.acknowledged,
      snoozedUntil: escalated ? null : old.snoozedUntil,
    );
  }

  void acknowledge(String id) {
    if (_alerts[id] case final alert?) {
      _alerts[id] = alert.copyWith(acknowledged: true);
    }
  }

  void snooze(String id, DateTime until) {
    if (_alerts[id] case final alert?) {
      _alerts[id] = alert.copyWith(snoozedUntil: until);
    }
  }
}

class _Period {
  _Period(this.start, this.last, this.clearing);
  final DateTime start;
  DateTime last;
  final bool clearing;
}
