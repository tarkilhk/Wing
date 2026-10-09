import 'package:flutter/scheduler.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/health_alert.dart';
import '../../theme/wing_theme.dart';
import 'health_alerts_scope.dart';
import 'health_alert_dialog.dart';

/// Animation and accessibility only. Incidents/settings belong to app owners.
class HealthAlertBell extends StatefulWidget {
  const HealthAlertBell({super.key});
  @override
  State<HealthAlertBell> createState() => _HealthAlertBellState();
}

class _HealthAlertBellState extends State<HealthAlertBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
  }

  HealthAlertsScope? _scope;
  final _seen = <String, String>{};
  bool _updateScheduled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = HealthAlertsScope.maybeOf(context);
    if (next?.alerts != _scope?.alerts) {
      _scope?.alerts.removeListener(_changed);
      _scope = next;
      _scope?.alerts.addListener(_changed);
      _seen.clear();
      for (final a in _scope?.alerts.alerts ?? <HealthAlert>[]) {
        _seen[a.id] = '${a.occurrence}:${a.remindsAt(DateTime.now())}';
      }
    }
    if (MediaQuery.disableAnimationsOf(context)) _motion.stop();
  }

  void _changed() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_updateScheduled) return;
      _updateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateScheduled = false;
        if (mounted) _changed();
      });
      return;
    }
    final scope = _scope;
    if (!mounted || scope == null) return;
    final now = DateTime.now(), current = <String, String>{};
    var arrived = false;
    for (final a in scope.alerts.alerts) {
      final fingerprint = '${a.occurrence}:${a.remindsAt(now)}';
      current[a.id] = fingerprint;
      if (a.remindsAt(now) && _seen[a.id] != fingerprint) arrived = true;
    }
    _seen
      ..clear()
      ..addAll(current);
    if (arrived &&
        scope.alerts.settings.settings.animateBell &&
        !MediaQuery.disableAnimationsOf(context)) {
      _motion.forward(from: 0);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final alerts = scope?.alerts.alerts ?? <HealthAlert>[];
    // Keep the title-row slot stable when an issue arrives.
    if (scope == null || alerts.isEmpty) {
      return const SizedBox(width: 48, height: 48);
    }
    final tokens = WingTokens.of(context);
    final active = alerts.any((a) => a.remindsAt(DateTime.now()));
    final color = !active
        ? tokens.muted
        : alerts.first.severity == HealthAlertSeverity.critical
        ? tokens.danger
        : tokens.warning;
    return IconButton(
      key: const ValueKey('health-alert-bell'),
      tooltip:
          'Health alerts: ${alerts.length} current ${alerts.length == 1 ? 'issue' : 'issues'}',
      onPressed: () => showHealthAlerts(context, scope),
      icon: AnimatedBuilder(
        animation: _motion,
        builder: (context, _) => Badge(
          label: ExcludeSemantics(
            child: Text(
              alerts.length > 99 ? '99+' : '${alerts.length}',
              textScaler: TextScaler.noScaling,
              style: const TextStyle(fontSize: 10),
            ),
          ),
          offset: const Offset(2, -4),
          backgroundColor: color,
          textColor: tokens.surface,
          child: Transform.rotate(
            angle: _motion.isAnimating
                ? math.sin(_motion.value * math.pi * 8) *
                      .22 *
                      (1 - _motion.value)
                : 0,
            alignment: Alignment.topCenter,
            child: Icon(Icons.notifications_none, color: color),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scope?.alerts.removeListener(_changed);
    _motion.dispose();
    super.dispose();
  }
}
