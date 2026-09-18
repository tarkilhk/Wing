import 'package:flutter/material.dart';
import '../../services/doctor_diagnostic.dart';
import '../../theme/wing_theme.dart';
import '../../services/administration_health.dart';
import 'admin_operations_page.dart';
import 'admin_widgets.dart';

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
    if (health.runtimeCheckedAt == null && !health.runtimeLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) health.refreshRuntimeIdentity();
      });
    }
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
    final generation = controller.beginDiagnostic(path, scope: scope);
    if (generation == null) return;
    var started = false;
    try {
      final action = await startAdminOperation(
        context,
        controller.server,
        path,
        title,
        controller.runtimeIdentity?['name'] as String?,
      );
      if (action != null) {
        controller.trackDiagnostic(path, action, generation: generation);
        started = true;
      }
    } finally {
      controller.finishDiagnostic(path, generation);
    }
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
        onRunAgain:
            _observations[path]?.status['running'] == false &&
                _observations[path]?.status['exit_code'] is int
            ? () async {
                Navigator.of(context).pop();
                await _run(path, title, scope, openResult: true);
              }
            : null,
        title: title,
        scope: controller.diagnosticScope(path) ?? scope,
        onObservation: (value) =>
            controller.observeDiagnostic(path, value, generation: generation),
      ),
    );
  }

  Widget _check(String title, String path, String scope) {
    final observation = _observations[path];
    final diagnosis =
        path == 'ops/doctor' && observation?.status['running'] == false
        ? DoctorDiagnostic.fromLines(
            observation?.status['lines'] as List? ?? [],
          )
        : null;
    final label = observation == null
        ? (health.starting.contains(path) ? 'Starting…' : 'Not run')
        : observation.readError != null
        ? 'Result refresh unavailable'
        : diagnosis?.title ??
              (observation.outcome == 'Completed'
                  ? 'Completed · Review results'
                  : observation.outcome);
    final warning = diagnosis?.hasIssues == true;
    final color = observation?.failed == true
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
    final identity = health.runtimeIdentity;
    final scope =
        identity?['label'] as String? ?? 'Runtime identity not checked';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                (context) =>
                    AdminLogsPage(server: health.server, runtimeLabel: scope),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(scope, style: Theme.of(context).textTheme.bodySmall),
        ),
        if (identity?['unavailable'] == true)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: health.runtimeLoading
                  ? null
                  : health.refreshRuntimeIdentity,
              child: const Text('Retry runtime identity'),
            ),
          ),
      ],
    );
  }
}
