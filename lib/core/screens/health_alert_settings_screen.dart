import 'package:flutter/material.dart';
import '../models/health_alert.dart';
import '../models/host_thresholds.dart';
import '../presentation/health_alert_presentation.dart';
import '../services/health_alert_settings_session.dart';
import '../widgets/wing_app_bar.dart';
import '../widgets/studio_error.dart';
import 'administration/admin_widgets.dart';

class HealthAlertSettingsScreen extends StatefulWidget {
  const HealthAlertSettingsScreen({super.key, required this.session});
  final HealthAlertSettingsSession session;
  @override
  State<HealthAlertSettingsScreen> createState() =>
      _HealthAlertSettingsScreenState();
}

class _HealthAlertSettingsScreenState extends State<HealthAlertSettingsScreen> {
  late HealthAlertSettings _baseline = widget.session.settings;
  late HealthAlertSettings _draft = _baseline;
  bool _saved = false;
  bool get _dirty => _draft != _baseline;
  void _edit(HealthAlertSettings value) => setState(() {
    _draft = value;
    _saved = false;
  });
  Future<void> _back() async {
    if (widget.session.saving) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard alert changes?'),
          actions: [
            IconButton(
              tooltip: 'Keep editing',
              onPressed: () => Navigator.pop(context, false),
              icon: const Icon(Icons.close),
            ),
            IconButton(
              tooltip: 'Discard changes',
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) => PopScope(
      canPop: !_dirty && !widget.session.saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: WingAppBar(
          context: context,
          title: const Text('Alert settings'),
          leading: BackButton(onPressed: _back),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const Text('This device', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            const Text(
              'Warn about problems that may affect Hermes. Checks run while Wing is open or monitoring work.',
            ),
            if (widget.session.error case final error?) StudioError(error),
            _toggle(
              'Health alerts',
              'Applies to active connections on this device.',
              _draft.enabled,
              (value) => _edit(_draft.copyWith(enabled: value)),
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
                      _draft.rules[metric]!.enabled
                          ? 'For ${_draft.rules[metric]!.minutes} min · clears below ${healthAlertPercentage(_draft.rules[metric]!.clearBelow)}%'
                          : 'Not watched',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${healthAlertPercentage(_draft.rules[metric]!.warnAbove)}%',
                        ),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                    onTap: widget.session.saving
                        ? null
                        : () async {
                            final rule = await showDialog<HealthAlertRule>(
                              context: context,
                              builder: (_) => _RuleEditor(
                                metric: metric,
                                initial: _draft.rules[metric]!,
                              ),
                            );
                            if (rule != null && mounted) {
                              _edit(
                                _draft.copyWith(
                                  rules: {..._draft.rules, metric: rule},
                                ),
                              );
                            }
                          },
                  ),
              ],
            ),
            const Text(
              'Reported critical memory or disk pressure alerts immediately when its rule is enabled.',
            ),
            const SizedBox(height: 16),
            const Text('Server & profile'),
            _toggle(
              'Server problems',
              'Observed connection or diagnostic failures.',
              _draft.server,
              (v) => _edit(_draft.copyWith(server: v)),
            ),
            _toggle(
              'Profile problems',
              'Observed access, connector or task failures.',
              _draft.profile,
              (v) => _edit(_draft.copyWith(profile: v)),
            ),
            const SizedBox(height: 16),
            const Text('When an issue arrives'),
            _toggle(
              'Animate the bell',
              'Ring once for a new issue or escalation.',
              _draft.animateBell,
              (v) => _edit(_draft.copyWith(animateBell: v)),
            ),
            _toggle(
              'Show a brief notice',
              'Keep working; tap the bell for details.',
              _draft.showNotice,
              (v) => _edit(_draft.copyWith(showNotice: v)),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _saved
                        ? 'Saved on this device'
                        : _dirty
                        ? 'Unsaved changes'
                        : 'This device',
                  ),
                ),
                IconButton(
                  tooltip: 'Reset draft',
                  onPressed:
                      widget.session.saving ||
                          (!_dirty && widget.session.error == null)
                      ? null
                      : () {
                          _baseline = widget.session.settings;
                          _edit(_baseline);
                        },
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: 'Save health alert settings',
                  onPressed:
                      widget.session.saving ||
                          (!_dirty && widget.session.error == null)
                      ? null
                      : () async {
                          if (await widget.session.save(
                                _draft,
                                expected: _baseline,
                              ) &&
                              mounted) {
                            setState(() {
                              _baseline = _draft;
                              _saved = true;
                            });
                          }
                        },
                  icon: widget.session.saving
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
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
    onChanged: widget.session.saving ? null : choose,
  );
}

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({required this.metric, required this.initial});
  final HostMetric metric;
  final HealthAlertRule initial;
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late bool _enabled = widget.initial.enabled;
  late final _warn = TextEditingController(
    text: healthAlertPercentage(widget.initial.warnAbove),
  );
  late final _clear = TextEditingController(
    text: healthAlertPercentage(widget.initial.clearBelow),
  );
  late final _minutes = TextEditingController(
    text: '${widget.initial.minutes}',
  );
  String? _error;
  void _apply() {
    try {
      final rule = HealthAlertRule(
        enabled: _enabled,
        warnAbove: double.parse(_warn.text),
        clearBelow: double.parse(_clear.text),
        minutes: int.parse(_minutes.text),
      );
      Navigator.pop(context, rule);
    } catch (_) {
      setState(
        () => _error = 'Use 0–100%, recovery below warning, and 1–30 minutes.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
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
                tooltip: 'Apply this rule to the settings draft',
                onPressed: _apply,
                icon: const Icon(Icons.check),
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
                    'Enabled',
                    Switch(
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                  ),
                  _field('Warn above', _warn, '%'),
                  _field('Clear below', _clear, '%'),
                  _field('Duration', _minutes, 'min'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Both limits must hold for this duration.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
  );
  Widget _field(String label, TextEditingController controller, String unit) =>
      _row(
        label,
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.end,
                onSubmitted: (_) => _apply(),
              ),
            ),
            const SizedBox(width: 6),
            Text(unit),
          ],
        ),
      );
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
    _minutes.dispose();
    super.dispose();
  }
}
