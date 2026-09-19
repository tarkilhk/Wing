import 'package:flutter/material.dart';
import '../../services/doctor_diagnostic.dart';
import '../../services/security_audit_report.dart';
import '../../theme/wing_theme.dart';
import '../../services/administration_health.dart';
import 'admin_operations_page.dart';
import 'admin_widgets.dart';

Future<bool> _startDiagnostic(
  BuildContext context,
  AdministrationHealth health,
  String path,
  String title, {
  bool confirm = true,
}) async {
  final generation = health.beginDiagnostic(
    path,
    scope: health.server.connectionLabel,
  );
  if (generation == null) return false;
  try {
    final action = await startAdminOperation(
      context,
      health.server,
      path,
      title,
      confirm: confirm,
      isActive: () => !health.isDisposed,
      onStarting: () => health.recordDiagnosticAttempt(path),
    );
    if (action == null) return false;
    health.trackDiagnostic(path, action, generation: generation);
    return true;
  } finally {
    health.finishDiagnostic(path, generation);
  }
}

/// Shared by Health entry and its Run all control. Profile selection never
/// invokes this connection-owned operation.
Future<void> runAllHealthDiagnostics(
  BuildContext context,
  AdministrationHealth health,
) async {
  if (!context.mounted ||
      !health.canStartDiagnostic('ops/doctor') ||
      !health.canStartDiagnostic('ops/security-audit')) {
    return;
  }
  await Future.wait([
    _startDiagnostic(context, health, 'ops/doctor', 'Doctor', confirm: false),
    _startDiagnostic(
      context,
      health,
      'ops/security-audit',
      'Security audit',
      confirm: false,
    ),
  ]);
}

/// Check missing or expired results once on Health entry. Profile changes do
/// not invoke this connection-owned work.
Future<void> refreshHealthDiagnostics(
  BuildContext context,
  AdministrationHealth health,
) async {
  if (!context.mounted) return;
  await Future.wait([
    for (final (path, title) in [
      ('ops/doctor', 'Doctor'),
      ('ops/security-audit', 'Security audit'),
    ])
      if (health.diagnosticNeedsRefresh(path))
        _startDiagnostic(context, health, path, title, confirm: false),
  ]);
}

/// Presents connection-owned observations retained across Health visits.
class AdminRuntimeHealth extends StatefulWidget {
  const AdminRuntimeHealth({super.key, required this.health});
  final AdministrationHealth health;
  @override
  State<AdminRuntimeHealth> createState() => _AdminRuntimeHealthState();
}

class _AdminRuntimeHealthState extends State<AdminRuntimeHealth> {
  AdministrationHealth get health => widget.health;
  Map<String, AdminDiagnosticObservation> get _observations =>
      health.diagnostics;

  @override
  void initState() {
    super.initState();
    health.addListener(_changed);
  }

  @override
  void didUpdateWidget(AdminRuntimeHealth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.health != health) {
      oldWidget.health.removeListener(_changed);
      health.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    health.removeListener(_changed);
    super.dispose();
  }

  Future<void> _run(
    String path,
    String title,
    String scope, {
    required bool openResult,
  }) async {
    final controller = health;
    final started = await _startDiagnostic(context, controller, path, title);
    if (started && mounted && identical(controller, health) && openResult) {
      await _result(path, title, scope);
    }
  }

  Future<void> _result(String path, String title, String scope) {
    final controller = health;
    final generation = controller.diagnosticGeneration(path);
    return adminPush(
      context,
      (context) => AdminActionPage(
        server: controller.server,
        action: _observations[path]!.action,
        initialObservation: _observations[path],
        onRunAgain: () async {
          Navigator.of(context).pop();
          await _run(path, title, scope, openResult: true);
        },
        title: title,
        scope: controller.diagnosticScope(path) ?? scope,
        onObservation: (value) =>
            controller.observeDiagnostic(path, value, generation: generation),
      ),
    );
  }

  Widget _check(String title, String path, String scope) {
    final observation = _observations[path];
    final audit = path == 'ops/security-audit' && observation != null
        ? SecurityAuditReport.fromStatus(observation.status)
        : null;
    final diagnosis =
        path == 'ops/doctor' && observation?.status['running'] == false
        ? DoctorDiagnostic.fromLines(
            observation?.status['lines'] as List? ?? [],
          )
        : null;
    final label = health.starting.contains(path)
        ? 'Starting…'
        : observation == null
        ? health.hasAttemptedDiagnostic(path)
              ? 'Start not confirmed'
              : 'Not run'
        : observation.readError != null
        ? 'Result refresh unavailable'
        : audit?.title ??
              diagnosis?.title ??
              (path == 'ops/security-audit' &&
                      observation.status['running'] == false &&
                      observation.status['exit_code'] == 1
                  ? 'Review audit findings'
                  : observation.outcome == 'Completed'
                  ? 'Completed · Review results'
                  : observation.outcome);
    final warning =
        diagnosis?.hasIssues == true || audit?.hasVulnerabilities == true;
    final color =
        audit?.hasHighSeverity == true ||
            (audit == null && observation?.failed == true)
        ? WingTokens.of(context).danger
        : warning
        ? WingTokens.of(context).warning
        : null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      minTileHeight: 64,
      minVerticalPadding: 8,
      leading: Icon(
        title == 'Doctor'
            ? Icons.medical_services_outlined
            : Icons.shield_outlined,
        color: color,
        size: 22,
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '$label${observation?.checkedAt != null ? ' · ${TimeOfDay.fromDateTime(observation!.checkedAt!).format(context)}' : ''}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
      trailing: observation == null
          ? TextButton(
              onPressed: health.starting.contains(path)
                  ? null
                  : () => _run(path, title, scope, openResult: false),
              child: const Text('Run'),
            )
          : const Icon(Icons.chevron_right, size: 20),
      onTap: health.starting.contains(path)
          ? null
          : () => observation == null
                ? _run(path, title, scope, openResult: true)
                : _result(path, title, scope),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = health.server.connectionLabel;
    final canRunAll =
        health.canStartDiagnostic('ops/doctor') &&
        health.canStartDiagnostic('ops/security-audit');
    final running =
        health.starting.isNotEmpty ||
        _observations.values.any((value) => value.status['running'] == true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Server',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Run all diagnostics',
              onPressed: canRunAll
                  ? () => runAllHealthDiagnostics(context, health)
                  : null,
              icon: running
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Running diagnostics',
                      ),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        AdminGroup(
          children: [
            _check('Doctor', 'ops/doctor', scope),
            _check('Security audit', 'ops/security-audit', scope),
            AdminRow(
              title: 'Logs',
              subtitle: 'Recent server activity',
              icon: Icons.subject,
              onTap: () => adminPush(
                context,
                (context) => AdminLogsPage(server: health.server),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
