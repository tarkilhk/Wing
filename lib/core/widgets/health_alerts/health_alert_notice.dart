import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../models/health_alert.dart';
import '../../theme/wing_theme.dart';
import 'health_alerts_scope.dart';

/// One transient notice per application, independent of how many headers are
/// mounted. Never opens a modal automatically or requests native notification.
class HealthAlertNotice extends StatefulWidget {
  const HealthAlertNotice({
    super.key,
    required this.child,
    required this.onOpenAlerts,
    required this.navigatorKey,
  });
  final Widget child;
  final VoidCallback onOpenAlerts;
  final GlobalKey<NavigatorState> navigatorKey;
  @override
  State<HealthAlertNotice> createState() => _HealthAlertNoticeState();
}

class _HealthAlertNoticeState extends State<HealthAlertNotice> {
  HealthAlertsScope? _scope;
  final _seen = <String, int>{};
  HealthAlert? _notice;
  Timer? _expiry;
  OverlayEntry? _entry;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = HealthAlertsScope.maybeOf(context);
    if (next?.alerts != _scope?.alerts) {
      _scope?.alerts.removeListener(_changed);
      _scope = next;
      _scope?.alerts.addListener(_changed);
      for (final a in _scope?.alerts.alerts ?? <HealthAlert>[]) {
        _seen[a.id] = a.occurrence;
      }
    }
  }

  void _changed() {
    if (!mounted || _scope == null) return;
    final alerts = _scope!.alerts.alerts;
    final fresh = alerts
        .where(
          (a) => _seen[a.id] != a.occurrence && a.remindsAt(DateTime.now()),
        )
        .firstOrNull;
    _seen
      ..clear()
      ..addEntries(alerts.map((a) => MapEntry(a.id, a.occurrence)));
    final visible =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (fresh != null &&
        visible &&
        _scope!.alerts.settings.settings.showNotice) {
      _expiry?.cancel();
      _notice = fresh;
      _show();
      _expiry = Timer(const Duration(milliseconds: 5500), () {
        if (mounted) _hide();
      });
    } else if (_notice != null &&
        (!visible || !alerts.any((a) => a.id == _notice!.id))) {
      _expiry?.cancel();
      _hide();
    }
  }

  void _hide() {
    _notice = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _show() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _notice != null) _show();
      });
      return;
    }
    final overlay = widget.navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    _entry = OverlayEntry(builder: _renderNotice);
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) => widget.child;
  Widget _renderNotice(BuildContext context) {
    final tokens = WingTokens.of(context), notice = _notice;
    if (notice == null) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 48,
      left: 16,
      right: 16,
      child: Material(
        color: tokens.raised,
        shape: RoundedRectangleBorder(
          borderRadius: WingRadius.card,
          side: BorderSide(
            color: notice.severity == HealthAlertSeverity.critical
                ? tokens.danger
                : tokens.warning,
          ),
        ),
        child: Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    _expiry?.cancel();
                    _hide();
                    widget.onOpenAlerts();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(notice.title),
                        Text(
                          notice.connectionLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Dismiss health notice',
                onPressed: () {
                  _expiry?.cancel();
                  _hide();
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scope?.alerts.removeListener(_changed);
    _expiry?.cancel();
    _hide();
    super.dispose();
  }
}
