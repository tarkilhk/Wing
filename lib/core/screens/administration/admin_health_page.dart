import '../../widgets/studio_select.dart';
import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import '../../widgets/profile_diagnostics_panel.dart';
import '../../services/profile_workspace_controller.dart';
import 'admin_widgets.dart';
import 'admin_operations_page.dart';
import 'admin_providers_page.dart';
import 'admin_connectors_page.dart';

class AdminHealthContent extends StatelessWidget {
  final AdministrationRepository server;
  final ProfileAdministration? profile;
  final Widget profileSelector;
  final ProfileWorkspaceData? workspace;
  final VoidCallback? onConnections;
  const AdminHealthContent({
    super.key,
    required this.server,
    required this.profile,
    required this.profileSelector,
    this.workspace,
    this.onConnections,
  });
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Runtime', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      AdminLoad(
        expand: false,
        load: server.runtimeIdentity,
        builder: (context, identity, refresh) {
          final label = identity['label'] as String;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label),
              if (identity['unavailable'] == true)
                TextButton(
                  onPressed: refresh,
                  child: const Text('Retry runtime identity'),
                ),
              const SizedBox(height: 8),
              AdminGroup(
                children: [
                  AdminRow(
                    title: 'Logs',
                    subtitle: 'Recent errors and bounded log search',
                    icon: Icons.subject,
                    onTap: () => adminPush(
                      context,
                      AdminLogsPage(server: server, runtimeLabel: label),
                    ),
                  ),
                  AdminRow(
                    title: 'Doctor',
                    subtitle: 'Run diagnostics without automatic repairs',
                    icon: Icons.health_and_safety_outlined,
                    onTap: () => startAdminOperation(
                      context,
                      server,
                      'ops/doctor',
                      'Doctor',
                      label,
                    ),
                  ),
                  AdminRow(
                    title: 'Security audit',
                    subtitle: 'Inspect backend policy and configuration',
                    icon: Icons.health_and_safety_outlined,
                    onTap: () => startAdminOperation(
                      context,
                      server,
                      'ops/security-audit',
                      'Security audit',
                      label,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 20),
      Text('Selected profile', style: Theme.of(context).textTheme.titleMedium),
      profileSelector,
      if (profile == null)
        const AdminNotice('Select an available profile to view its health.')
      else ...[
        AdminGroup(
          children: [
            AdminRow(
              title: 'Usage',
              subtitle: 'Rolling time ranges and model detail',
              icon: Icons.bar_chart,
              onTap: () =>
                  adminPush(context, AdminUsagePage(profile: profile!)),
            ),
          ],
        ),
        if (workspace != null && onConnections != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ProfileDiagnosticsPanel(
              workspace: workspace!,
              connectionLabel: server.connectionLabel,
              onManageConnections: onConnections!,
              onReviewProviderAccess: () => adminPush(
                context,
                AdminProvidersPage(profile: profile!, shared: false),
              ),
              onReviewConnectors: () =>
                  adminPush(context, AdminConnectorsPage(profile: profile!)),
            ),
          ),
      ],
    ],
  );
}

class AdminUsagePage extends StatefulWidget {
  final ProfileAdministration profile;
  const AdminUsagePage({super.key, required this.profile});
  @override
  State<AdminUsagePage> createState() => _AdminUsagePageState();
}

class _AdminUsagePageState extends State<AdminUsagePage> {
  int _days = 7;
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Usage',
    scope: widget.profile.label,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: StudioSelect<int>(
            value: _days,
            label: 'Time range',
            options: [
              for (final days in [1, 7, 30, 90, 365])
                (
                  value: days,
                  label: days == 1 ? 'Last 24 hours' : 'Last $days days',
                ),
            ],
            onChanged: (v) => setState(() => _days = v!),
          ),
        ),
        Expanded(
          child: AdminLoad(
            key: ValueKey(_days),
            load: () =>
                widget.profile.read('analytics/models', {'days': '$_days'}),
            builder: (context, data, refresh) {
              final models = administrationRows(data['models']);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const AdminNotice(
                    'Hermes usage estimates. These are not provider invoices.',
                  ),
                  TextButton(onPressed: refresh, child: const Text('Refresh')),
                  if (models.isEmpty)
                    const AdminNotice(
                      'No recorded model usage in this period.',
                    ),
                  for (final model in models)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AdminGroup(
                        children: [
                          ListTile(
                            title: Text('${model['model'] ?? 'Unknown model'}'),
                            subtitle: Text(
                              '${model['provider'] ?? 'Provider unavailable'}',
                            ),
                          ),
                          for (final key in [
                            'sessions',
                            'api_calls',
                            'input_tokens',
                            'output_tokens',
                            'estimated_cost',
                          ])
                            if (model[key] is num)
                              ListTile(
                                title: Text(switch (key) {
                                  'input_tokens' => 'Input tokens',
                                  'output_tokens' => 'Output tokens',
                                  'estimated_cost' => 'Estimated cost · USD',
                                  'api_calls' => 'Calls',
                                  _ => 'Sessions',
                                }),
                                subtitle: Text(
                                  '${model[key]}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
