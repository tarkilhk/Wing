import '../models/host_thresholds.dart';

String healthAlertMetricLabel(HostMetric metric) => switch (metric) {
  HostMetric.memoryUsedPercent => 'Memory usage',
  HostMetric.diskUsedPercent => 'Disk usage',
  _ => 'CPU usage',
};

/// Preserve editable precision while omitting the redundant decimal for integers.
String healthAlertPercentage(double value) => value == value.truncateToDouble()
    ? value.toInt().toString()
    : value.toString();
