import 'package:flutter/material.dart';
import '../../models/health_alert.dart';
import '../../theme/wing_theme.dart';
import 'health_alerts_scope.dart';

Future<void> showHealthAlerts(BuildContext context, HealthAlertsScope scope) =>
    showDialog<void>(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 210),
              reverseDuration: Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
            ),
      builder: (_) => _HealthAlertDialog(scope: scope),
    );

class _HealthAlertDialog extends StatefulWidget {
  const _HealthAlertDialog({required this.scope});
  final HealthAlertsScope scope;
  @override
  State<_HealthAlertDialog> createState() => _HealthAlertDialogState();
}

class _HealthAlertDialogState extends State<_HealthAlertDialog> {
  String? _selected;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.scope.alerts,
    builder: (context, _) {
      final alerts = widget.scope.alerts.alerts;
      var index = alerts.indexWhere((a) => a.id == _selected);
      if (index < 0) index = 0;
      final alert = alerts.isEmpty ? null : alerts[index];
      final tokens = WingTokens.of(context);
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Health alerts',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close alerts',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: alert == null
                      ? const Text('No current health alerts.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (alerts.length > 1)
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Previous issue',
                                    onPressed: () => setState(
                                      () => _selected =
                                          alerts[(index - 1 + alerts.length) %
                                                  alerts.length]
                                              .id,
                                    ),
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${index + 1} of ${alerts.length}',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Next issue',
                                    onPressed: () => setState(
                                      () => _selected =
                                          alerts[(index + 1) % alerts.length]
                                              .id,
                                    ),
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
                            Text(
                              alert.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color:
                                        alert.severity ==
                                            HealthAlertSeverity.critical
                                        ? tokens.danger
                                        : tokens.warning,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${alert.scope.name} · ${alert.connectionLabel}${alert.profileName == null ? '' : ' · ${alert.profileName}'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            Text(alert.detail),
                            const SizedBox(height: 12),
                            Text(
                              '${alert.lastKnown ? 'Last known' : 'Observed'} ${TimeOfDay.fromDateTime(alert.observedAt.toLocal()).format(context)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (alert.lastKnown)
                              const Text(
                                'A fresh reading is needed to confirm recovery.',
                              ),
                            if (alert.acknowledged)
                              const Text(
                                'Acknowledged. This issue remains until it recovers.',
                              ),
                            if (alert.snoozedUntil != null &&
                                alert.snoozedUntil!.isAfter(DateTime.now()))
                              Text(
                                'Reminders paused until ${TimeOfDay.fromDateTime(alert.snoozedUntil!.toLocal()).format(context)}.',
                              ),
                          ],
                        ),
                ),
              ),
              if (alert != null) ...[
                const Divider(height: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Acknowledge issue',
                      onPressed: alert.acknowledged
                          ? null
                          : () => widget.scope.alerts.acknowledge(alert),
                      icon: const Icon(Icons.done),
                    ),
                    IconButton(
                      tooltip: 'Pause reminders for 30 minutes',
                      onPressed: () => widget.scope.alerts.snooze(alert),
                      icon: const Icon(Icons.notifications_paused_outlined),
                    ),
                    IconButton(
                      tooltip: 'Open Hermes health',
                      onPressed: () {
                        Navigator.pop(context);
                        widget.scope.openHealth(alert);
                      },
                      icon: const Icon(Icons.health_and_safety_outlined),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
