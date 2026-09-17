import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import 'admin_operations_page.dart';
import 'admin_widgets.dart';

/// Keeps server observations while visiting results or switching profile tabs.
class AdminRuntimeHealth extends StatefulWidget {
  const AdminRuntimeHealth({
    super.key,
    required this.server,
    this.refreshRevision = 0,
  });
  final AdministrationRepository server;
  final int refreshRevision;
  @override
  State<AdminRuntimeHealth> createState() => _AdminRuntimeHealthState();
}

class _AdminRuntimeHealthState extends State<AdminRuntimeHealth> {
  final _observations = <String, AdminDiagnosticObservation>{};
  final _starting = <String>{};
  void _observe(String path, AdminDiagnosticObservation value) {
    if (mounted) setState(() => _observations[path] = value);
  }

  Future<void> _run(String path, String title, String scope) async {
    if (_starting.contains(path)) return;
    setState(() => _starting.add(path));
    try {
      await startAdminOperation(
        context,
        widget.server,
        path,
        title,
        scope,
        onObservation: (value) => _observe(path, value),
      );
    } finally {
      if (mounted) setState(() => _starting.remove(path));
    }
  }

  Future<void> _result(String path, String title, String scope) => adminPush(
    context,
    AdminActionPage(
      server: widget.server,
      action: _observations[path]!.action,
      initialObservation: _observations[path],
      title: title,
      scope: scope,
      onObservation: (value) => _observe(path, value),
    ),
  );

  Widget _check(String title, String path, String scope) {
    final observation = _observations[path];
    final status = observation?.outcome ?? 'Not checked';
    final checked = observation?.checkedAt;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          if (observation?.readError != null)
            const AdminAttention('Result refresh unavailable')
          else if (observation?.failed == true)
            AdminAttention(status)
          else
            Text(status, style: Theme.of(context).textTheme.bodyMedium),
          if (checked != null)
            Text(
              'Checked ${TimeOfDay.fromDateTime(checked).format(context)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 4),
          Text(
            observation?.nextStep ??
                (title == 'Doctor'
                    ? 'Check the server’s configuration and dependencies. No automatic repairs.'
                    : 'Inspect the server’s policy and security configuration.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              if (observation != null)
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
                    _starting.contains(path) ||
                        observation != null &&
                            (observation.status['running'] == true ||
                                observation.status['exit_code'] == null)
                    ? null
                    : () => _run(path, title, scope),
                child: Text(
                  observation == null ? 'Run $title' : 'Run $title again',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AdminLoad(
    key: ValueKey(widget.refreshRevision),
    expand: false,
    load: () async => {
      ...await widget.server.runtimeIdentity(),
      'observedAt': DateTime.now(),
    },
    builder: (context, identity, refresh) {
      final scope = identity['label'] as String;
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
          Text(
            'Identity checked ${TimeOfDay.fromDateTime(identity['observedAt'] as DateTime).format(context)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (identity['unavailable'] == true) ...[
            const SizedBox(height: 8),
            const AdminAttention('Runtime identity unavailable'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: refresh,
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
                  AdminLogsPage(server: widget.server, runtimeLabel: scope),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}
