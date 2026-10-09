import 'package:flutter/foundation.dart';
import '../models/health_alert.dart';
import '../models/health_alert_evaluator.dart';
import '../models/health_finding.dart';
import '../models/host_resources.dart';
import '../models/host_thresholds.dart';
import 'administration_health.dart';
import 'health_alert_settings_session.dart';
import 'host_resources_session.dart';
import 'server_connection_status.dart';

/// Connection-owned evaluator borrowing canonical observations. Owns only its
/// watch demand and incidents; never runs diagnostics or duplicates data reads.
class HealthAlertsSession extends ChangeNotifier {
  HealthAlertsSession({
    required this.host,
    required this.health,
    required this.connection,
    required this.settings,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _evaluator = HealthAlertEvaluator(
         connectionIdentity: host.connectionIdentity,
         connectionLabel: host.scopeLabel,
       ) {
    _watch = host.watch(interval: const Duration(seconds: 15), active: false);
    _lastSettings = settings.settings;
    host.addListener(_changed);
    health.addListener(_changed);
    connection.addListener(_changed);
    settings.addListener(_settingsChanged);
  }
  final HostResourcesSession host;
  final AdministrationHealth health;
  final ServerConnectionStatus connection;
  final HealthAlertSettingsSession settings;
  final DateTime Function() _now;
  final HealthAlertEvaluator _evaluator;
  late final HostResourcesWatch _watch;
  bool _active = false;
  HealthAlertSettings? _lastSettings;
  List<HealthAlert> get alerts => _evaluator.alerts;
  List<Object> _published = const [];
  bool get _wantsHost =>
      settings.settings.enabled &&
      settings.settings.rules.values.any((rule) => rule.enabled);
  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    _evaluator.resetPeriods();
    _watch.setActive(value && _wantsHost);
    if (value) {
      _changed();
    } else {
      for (final alert in alerts) {
        _evaluator.unknown(alert.id);
      }
      _publish();
    }
  }

  void _settingsChanged() {
    if (identical(_lastSettings, settings.settings)) return;
    final previous = _lastSettings;
    _lastSettings = settings.settings;
    for (final metric in hostAlertMetrics) {
      final old = previous?.rules[metric];
      final rule = settings.settings.rules[metric]!;
      if (old == null ||
          (
                old.enabled,
                old.warnAbove,
                old.clearBelow,
                old.alertMinutes,
                old.clearMinutes,
              ) !=
              (
                rule.enabled,
                rule.warnAbove,
                rule.clearBelow,
                rule.alertMinutes,
                rule.clearMinutes,
              )) {
        _evaluator.remove(_evaluator.hostKey(metric));
      }
    }
    // A new rule starts a new sustained period under its own limits.
    _evaluator.resetPeriods();
    _watch.setActive(_active && _wantsHost);
    _changed();
  }

  void _changed() {
    final policy = settings.settings;
    if (!policy.enabled) {
      _evaluator.clear();
      _publish();
      return;
    }
    // Disabled scopes remove their incidents even while collection is paused.
    for (final alert in alerts) {
      if (alert.scope == HealthAlertScope.server && !policy.server ||
          alert.scope == HealthAlertScope.profile && !policy.profile) {
        _evaluator.remove(alert.id);
      }
    }
    for (final metric in hostAlertMetrics) {
      if (!policy.rules[metric]!.enabled) {
        _evaluator.remove(_evaluator.hostKey(metric));
      }
    }
    if (!_active) {
      _publish();
      return;
    }
    final now = _now(), data = host.state;
    if (!data.refreshing) {
      final current = data.stats.isCurrent(now, const Duration(seconds: 30));
      final values = HostThresholdPolicy([
        for (final metric in hostAlertMetrics)
          HostThreshold(metric, policy.rules[metric]!.warnAbove),
      ]).evaluate(data.stats, now: now);
      final pressure = data.pressure.isCurrent(now, const Duration(seconds: 30))
          ? data.pressure.value
          : null;
      for (final result in values) {
        final metric = result.threshold.metric;
        final reported = switch (metric) {
          HostMetric.memoryUsedPercent => pressure?.memoryAt(now),
          HostMetric.diskUsedPercent => pressure?.disk,
          _ => HostPressure.ok,
        };
        _evaluator.host(
          metric: metric,
          rule: policy.rules[metric]!,
          now: now,
          sampledAt: current
              ? data.stats.readAt
              : reported == HostPressure.critical
              ? data.pressure.readAt
              : null,
          value: result.value,
          critical: reported == HostPressure.critical,
          pressureKnown: reported != null && reported != HostPressure.unknown,
        );
      }
    }
    if (policy.server) {
      _evaluator.finding(
        key: '${host.connectionIdentity}:server:connection',
        title: 'Connection needs refresh',
        detail:
            '${connection.problem ?? connection.description}\n'
            'Automatic recovery has stopped. Refresh the connection to try again.',
        scope: HealthAlertScope.server,
        at: now,
        failed: connection.requiresManualRefresh,
      );
    }
    for (final alert in alerts) {
      if (alert.scope == HealthAlertScope.profile &&
          alert.profileName != health.profileName) {
        _evaluator.unknown(alert.id);
      }
    }
    if (health.profileName case final name? when policy.profile) {
      for (final finding in health.profileFindings) {
        final at = finding.checkedAt;
        final current =
            at != null &&
            !now.isBefore(at) &&
            now.difference(at) < health.maxAge;
        _evaluator.finding(
          key: '${host.connectionIdentity}:profile:$name:${finding.title}',
          title: finding.title,
          detail: finding.detail,
          scope: HealthAlertScope.profile,
          profileName: name,
          at: at,
          failed:
              at == null ||
                  now.isBefore(at) ||
                  finding.status == AdministrationHealthStatus.unknown
              ? null
              : finding.status == AdministrationHealthStatus.failure ||
                    finding.status == AdministrationHealthStatus.warning,
          severity: finding.status == AdministrationHealthStatus.failure
              ? HealthAlertSeverity.critical
              : HealthAlertSeverity.warning,
        );
        if (!current) {
          _evaluator.unknown(
            '${host.connectionIdentity}:profile:$name:${finding.title}',
          );
        }
      }
    }
    _publish();
  }

  void acknowledge(String id) {
    _evaluator.acknowledge(id);
    _publish();
  }

  void snooze(String id) {
    _evaluator.snooze(id, _now().add(const Duration(minutes: 30)));
    _publish();
  }

  void _publish() {
    final next = alerts
        .map(
          (a) => (
            a.id,
            a.title,
            a.detail,
            a.scope,
            a.severity,
            a.observedAt,
            a.occurrence,
            a.profileName,
            a.lastKnown,
            a.acknowledged,
            a.snoozedUntil,
          ),
        )
        .toList();
    if (listEquals(_published, next)) return;
    _published = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _watch.close();
    host.removeListener(_changed);
    health.removeListener(_changed);
    connection.removeListener(_changed);
    settings.removeListener(_settingsChanged);
    super.dispose();
  }
}
