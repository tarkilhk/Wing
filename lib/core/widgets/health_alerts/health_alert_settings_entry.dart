import 'package:flutter/material.dart';
import '../../models/host_thresholds.dart';
import '../../presentation/health_alert_presentation.dart';
import '../../screens/health_alert_settings_screen.dart';
import 'health_alerts_scope.dart';

class HealthAlertSettingsEntry extends StatelessWidget {
  const HealthAlertSettingsEntry({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = HealthAlertsScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final session = scope.alerts.settings;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final policy = session.settings;
        final summary = !policy.enabled
            ? 'Off'
            : [
                for (final e in policy.rules.entries)
                  if (e.value.enabled)
                    '${switch (e.key) {
                      HostMetric.memoryUsedPercent => 'RAM',
                      HostMetric.diskUsedPercent => 'Disk',
                      _ => 'CPU',
                    }} >${healthAlertPercentage(e.value.warnAbove)}%',
              ].join(' · ');
        return Column(
          children: [
            ListTile(
              key: const ValueKey('health-alert-settings-entry'),
              contentPadding: EdgeInsets.zero,
              minVerticalPadding: 4,
              leading: const Icon(Icons.notifications_none),
              title: const Text('Alert settings'),
              subtitle: Text(
                'This device${summary.isEmpty ? '' : ' · $summary'}',
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => HealthAlertSettingsScreen(session: session),
                ),
              ),
            ),
            const Divider(height: 1),
          ],
        );
      },
    );
  }
}
