import 'package:flutter/material.dart';
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

  Future<void> _run(String path, String title, String scope) async {
    final controller = health;
    final generation = controller.beginDiagnostic(path, scope: scope);
    if (generation == null) return;
    try {
      await startAdminOperation(
        context,
        controller.server,
        path,
        title,
        scope,
        onObservation: (value) =>
            controller.observeDiagnostic(path, value, generation: generation),
      );
    } finally {
      controller.finishDiagnostic(path, generation);
    }
  }

  Future<void> _result(String path, String title, String scope) {
    final controller = health;
    final generation = controller.diagnosticGeneration(path);
    return adminPush(
      context,
      AdminActionPage(
        server: controller.server,
        action: _observations[path]!.action,
        initialObservation: _observations[path],
        title: title,
        scope: controller.diagnosticScope(path) ?? scope,
        onObservation: (value) =>
            controller.observeDiagnostic(path, value, generation: generation),
      ),
    );
  }

  Widget _check(String title, String path, String scope) {
    final observation = _observations[path];
    final status = observation?.outcome ?? 'Not checked';
    final checked = observation?.checkedAt;
    if (observation == null) {
      final label = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          Text('Not checked', style: Theme.of(context).textTheme.bodySmall),
        ],
      );
      final action = TextButton(
        onPressed: health.starting.contains(path)
            ? null
            : () => _run(path, title, scope),
        child: Text('Run $title'),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: MediaQuery.textScalerOf(context).scale(16) >= 20
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  label,
                  Align(alignment: Alignment.centerLeft, child: action),
                ],
              )
            : Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 8),
                  action,
                ],
              ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (health.diagnosticScope(path) != null &&
              health.diagnosticScope(path) != scope)
            Text(
              health.diagnosticScope(path)!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 4),
          if (observation.readError != null)
            const AdminAttention('Result refresh unavailable')
          else if (observation.failed == true)
            AdminAttention(status)
          else
            Text(status, style: Theme.of(context).textTheme.bodyMedium),
          if (checked != null)
            Text(
              'Checked ${TimeOfDay.fromDateTime(checked).format(context)}${health.isStale(checked) ? ' · Stale observation' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 4),
          Text(
            observation.nextStep,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _result(path, title, scope),
                child: Text(
                  observation.status['running'] == true
                      ? 'View progress'
                      : 'Review output',
                ),
              ),
              TextButton(
                onPressed:
                    health.starting.contains(path) ||
                        observation.status['running'] == true ||
                        observation.status['exit_code'] == null
                    ? null
                    : () => _run(path, title, scope),
                child: Text('Run $title again'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identity = health.runtimeIdentity;
    final scope =
        identity?['label'] as String? ?? 'Runtime identity not checked';
    final checks =
        [('Doctor', 'ops/doctor'), ('Security audit', 'ops/security-audit')]
          ..sort(
            (a, b) => (_observations[b.$2]?.failed == true ? 1 : 0).compareTo(
              _observations[a.$2]?.failed == true ? 1 : 0,
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(scope, style: Theme.of(context).textTheme.bodyMedium),
        if (identity?['unavailable'] == false &&
            health.overview != null &&
            identity?['name'] != health.overview!.profile.name)
          Text(
            'The running agent uses a different profile.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (health.runtimeCheckedAt case final checked?)
          Text(
            'Identity checked ${TimeOfDay.fromDateTime(checked).format(context)}${health.isStale(checked) ? ' · Stale observation' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (identity?['unavailable'] == true) ...[
          const SizedBox(height: 8),
          const AdminAttention('Runtime identity unavailable'),
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
        const SizedBox(height: 12),
        AdminGroup(
          children: [
            for (final check in checks) _check(check.$1, check.$2, scope),
          ],
        ),
        const SizedBox(height: 12),
        AdminGroup(
          children: [
            AdminRow(
              title: 'Logs',
              subtitle: 'Inspect recent server activity',
              icon: Icons.subject,
              onTap: () => adminPush(
                context,
                AdminLogsPage(server: health.server, runtimeLabel: scope),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
