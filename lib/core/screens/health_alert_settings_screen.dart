import 'package:flutter/material.dart';
import '../models/health_alert.dart';
import '../models/host_thresholds.dart';
import '../presentation/health_alert_presentation.dart';
import '../services/health_alert_settings_session.dart';
import '../widgets/wing_app_bar.dart';
import '../widgets/studio_error.dart';
import 'administration/admin_widgets.dart';

class HealthAlertSettingsScreen extends StatelessWidget {
  const HealthAlertSettingsScreen({super.key, required this.session});
  final HealthAlertSettingsSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final settings = session.value;
      return Scaffold(
        appBar: WingAppBar(
          context: context,
          title: const Text('Alert settings'),
          leading: const BackButton(),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const Text('This device', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            const Text(
              'Warn about problems that may affect Hermes. Checks run while Wing is open or monitoring work.',
            ),
            _SaveError(session: session),
            _toggle(
              'Health alerts',
              'Applies to active connections on this device.',
              settings.enabled,
              (value) =>
                  session.update((current) => current.copyWith(enabled: value)),
            ),
            const Text('Host thresholds'),
            AdminGroup(
              children: [
                for (final metric in hostAlertMetrics)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    minVerticalPadding: 4,
                    leading: Icon(switch (metric) {
                      HostMetric.memoryUsedPercent => Icons.memory,
                      HostMetric.diskUsedPercent => Icons.storage_outlined,
                      _ => Icons.developer_board_outlined,
                    }),
                    title: Text(healthAlertMetricLabel(metric)),
                    subtitle: Text(
                      settings.rules[metric]!.enabled
                          ? 'Alert after ${settings.rules[metric]!.alertMinutes} min · clear below ${healthAlertPercentage(settings.rules[metric]!.clearBelow)}% after ${settings.rules[metric]!.clearMinutes} min'
                          : settings.rules[metric]!.nativeCriticalEnabled
                          ? 'Native critical pressure only'
                          : 'Not watched',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (settings.rules[metric]!.enabled)
                          Text(
                            '${healthAlertPercentage(settings.rules[metric]!.warnAbove)}%',
                          ),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          _RuleEditor(metric: metric, session: session),
                    ),
                  ),
              ],
            ),
            const Text(
              'Native critical pressure alerts immediately when enabled.',
            ),
            const SizedBox(height: 16),
            const Text('Server & profile'),
            _toggle(
              'Server problems',
              'Observed connection failures.',
              settings.server,
              (value) =>
                  session.update((current) => current.copyWith(server: value)),
            ),
            _toggle(
              'Profile problems',
              'Observed access, connector or task failures.',
              settings.profile,
              (value) =>
                  session.update((current) => current.copyWith(profile: value)),
            ),
            const SizedBox(height: 16),
            const Text('When an issue arrives'),
            _toggle(
              'Animate the bell',
              'Ring once for a new issue or escalation.',
              settings.animateBell,
              (value) => session.update(
                (current) => current.copyWith(animateBell: value),
              ),
            ),
            _toggle(
              'Show a brief notice',
              'Keep working; tap the bell for details.',
              settings.showNotice,
              (value) => session.update(
                (current) => current.copyWith(showNotice: value),
              ),
            ),
          ],
        ),
      );
    },
  );
  Widget _toggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> choose,
  ) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: choose,
  );
}

class _SaveError extends StatelessWidget {
  const _SaveError({required this.session});
  final HealthAlertSettingsSession session;
  @override
  Widget build(BuildContext context) => session.error == null
      ? const SizedBox.shrink()
      : Row(
          children: [
            Expanded(child: StudioError(session.error!)),
            IconButton(
              tooltip: 'Retry saving alert settings',
              onPressed: () => session.retry(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        );
}

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({required this.metric, required this.session});
  final HostMetric metric;
  final HealthAlertSettingsSession session;
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  HealthAlertRule get _rule => widget.session.value.rules[widget.metric]!;
  late final _warn = TextEditingController(
    text: healthAlertPercentage(_rule.warnAbove),
  );
  late final _clear = TextEditingController(
    text: healthAlertPercentage(_rule.clearBelow),
  );
  late final _alertMinutes = TextEditingController(
    text: '${_rule.alertMinutes}',
  );
  late final _clearMinutes = TextEditingController(
    text: '${_rule.clearMinutes}',
  );
  String? _error;
  void _edit(String _) {
    try {
      final warning = double.parse(_warn.text);
      final recovery = double.parse(_clear.text);
      final alertMinutes = int.parse(_alertMinutes.text);
      final clearMinutes = int.parse(_clearMinutes.text);
      widget.session.updateRule(
        widget.metric,
        (current) => current.copyWith(
          warnAbove: warning,
          clearBelow: recovery,
          alertMinutes: alertMinutes,
          clearMinutes: clearMinutes,
        ),
      );
      setState(() => _error = null);
    } on FormatException {
      _invalid();
    } on ArgumentError catch (error) {
      if (error.name == 'clearBelow') {
        setState(
          () => _error =
              'Not saved: clear below ${_clear.text}% must be lower than alert above ${_warn.text}%.',
        );
      } else {
        _invalid();
      }
    }
  }

  void _invalid() => setState(
    () => _error =
        'Not saved: use 0–100%, recovery below warning, and 1–30 minutes.',
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * .85,
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
                    healthAlertMetricLabel(widget.metric),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Close rule editor',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _row(
                      'Usage warning',
                      Switch(
                        value: _rule.enabled,
                        onChanged: (value) => widget.session.updateRule(
                          widget.metric,
                          (current) => current.copyWith(enabled: value),
                        ),
                      ),
                    ),
                    _condition(
                      'Alert after',
                      _alertMinutes,
                      'if above',
                      _warn,
                      'Warning',
                    ),
                    _condition(
                      'Clear after',
                      _clearMinutes,
                      'if below',
                      _clear,
                      'Recovery',
                    ),
                    if (healthAlertNativeCriticalLabel(widget.metric)
                        case final label?) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        title: Text(label),
                        subtitle: Text(
                          healthAlertNativeCriticalDetail(widget.metric),
                        ),
                        value: _rule.nativeCriticalEnabled,
                        onChanged: (value) => widget.session.updateRule(
                          widget.metric,
                          (current) =>
                              current.copyWith(nativeCriticalEnabled: value),
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _SaveError(session: widget.session),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: StudioError(_error!),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _condition(
    String after,
    TextEditingController duration,
    String comparison,
    TextEditingController percent,
    String label,
  ) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: _labelWidth(['Alert after', 'Clear after']),
                child: Text(
                  after,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              _input('$label duration', duration, 'min', decimal: false),
            ],
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: _labelWidth(['if above', 'if below']),
                child: Text(
                  comparison,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              _input('$label threshold', percent, '%', decimal: true),
            ],
          ),
        ],
      ),
    ),
  );

  double _labelWidth(List<String> labels) {
    var width = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      if (painter.width > width) width = painter.width;
      painter.dispose();
    }
    return width;
  }

  Widget _input(
    String label,
    TextEditingController controller,
    String unit, {
    required bool decimal,
  }) {
    final large = MediaQuery.textScalerOf(context).scale(16) >= 24;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '${healthAlertMetricLabel(widget.metric)} $label',
          child: SizedBox(
            width: decimal ? (large ? 112 : 64) : 48,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.numberWithOptions(decimal: decimal),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 8,
                ),
              ),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.end,
              onChanged: _edit,
              onSubmitted: _edit,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(unit),
      ],
    );
  }

  Widget _row(String label, Widget control) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Semantics(
            label: '${healthAlertMetricLabel(widget.metric)} $label',
            child: SizedBox(
              width: MediaQuery.textScalerOf(context).scale(16) >= 24
                  ? 132
                  : 112,
              child: control,
            ),
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    _warn.dispose();
    _clear.dispose();
    _alertMinutes.dispose();
    _clearMinutes.dispose();
    super.dispose();
  }
}
