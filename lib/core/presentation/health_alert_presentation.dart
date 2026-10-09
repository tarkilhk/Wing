import '../models/host_thresholds.dart';
import '../models/health_alert.dart';

String? healthAlertTriggerSummary(HealthAlert alert) {
  final trigger = alert.trigger;
  if (trigger == null) return null;
  final value = trigger.usedPercent;
  final usage = value == null
      ? 'Usage unavailable'
      : '${healthAlertPercentage(value)}% used';
  return trigger.criticalPressure
      ? '$usage · critical pressure reported'
      : '$usage · above ${healthAlertPercentage(trigger.warningAbovePercent)}% for ${trigger.alertMinutes} min';
}

String healthAlertMetricLabel(HostMetric metric) => switch (metric) {
  HostMetric.memoryUsedPercent => 'Memory usage',
  HostMetric.diskUsedPercent => 'Disk usage',
  _ => 'CPU usage',
};

/// Preserve editable precision while omitting the redundant decimal for integers.
String healthAlertPercentage(double value) => value == value.truncateToDouble()
    ? value.toInt().toString()
    : value.toString();
