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
      Text('Selected profile', style: Theme.of(context).textTheme.titleMedium),
      profileSelector,
      if (profile == null)
        const AdminNotice('Select an available profile to view its health.')
      else ...[
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
      ],
      Text('Runtime', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      AdminLoad(
        expand: false,
        load: () async => {
          ...await server.runtimeIdentity(),
          'observedAt': DateTime.now(),
        },
        builder: (context, identity, refresh) {
          final label = identity['label'] as String;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label),
              Text(
                'Identity checked ${TimeOfDay.fromDateTime(identity['observedAt'] as DateTime).format(context)} · Diagnostics run on request',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
  String _sort = 'estimated_cost';
  bool valid(Object? value) => value is num && value.isFinite && value >= 0;
  String number(BuildContext context, Object? value, {bool money = false}) =>
      !valid(value)
      ? 'Unavailable'
      : money
      ? 'USD ${(value as num).toStringAsFixed(2)}'
      : MaterialLocalizations.of(context).formatDecimal((value as num).toInt());

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
            onChanged: (value) => setState(() => _days = value!),
          ),
        ),
        Expanded(
          child: AdminLoad(
            key: ValueKey(_days),
            load: () =>
                widget.profile.read('analytics/models', {'days': '$_days'}),
            builder: (context, data, refresh) {
              final models = administrationRows(data['models']);
              models.sort((a, b) {
                if (_sort == 'model') {
                  return '${a['model']}'.compareTo('${b['model']}');
                }
                final aValue = a[_sort], bValue = b[_sort];
                if (!valid(aValue)) return valid(bValue) ? 1 : 0;
                if (!valid(bValue)) return -1;
                return (bValue as num).compareTo(aValue as num);
              });
              final known = models
                  .where((model) => valid(model['estimated_cost']))
                  .toList();
              final total = known.fold<double>(
                0,
                (sum, model) =>
                    sum + (model['estimated_cost'] as num).toDouble(),
              );
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Text(
                    'Where your agent spends its time',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const AdminNotice(
                    'Hermes usage estimates. These are not provider invoices.',
                  ),
                  StudioSelect<String>(
                    value: _sort,
                    label: 'Sort models',
                    options: const [
                      (value: 'estimated_cost', label: 'Estimated cost'),
                      (value: 'api_calls', label: 'Calls'),
                      (value: 'input_tokens', label: 'Input tokens'),
                      (value: 'output_tokens', label: 'Output tokens'),
                      (value: 'model', label: 'Model name'),
                    ],
                    onChanged: (value) => setState(() => _sort = value!),
                  ),
                  const SizedBox(height: 12),
                  if (models.isEmpty)
                    const AdminNotice(
                      'No recorded model usage in this period.',
                    ),
                  if (models.isNotEmpty)
                    Text(
                      'Cost bars compare ${known.length} of ${models.length} models with reported costs. Total reported: ${number(context, total, money: true)}.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 12),
                  AdminGroup(
                    children: [
                      for (final model in models)
                        ExpansionTile(
                          key: PageStorageKey(
                            'usage:$_days:${model['provider']}:${model['model']}',
                          ),
                          title: Text(
                            '${model['model'] ?? 'Unknown model'}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '${model['provider'] ?? 'Provider unavailable'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${number(context, model['api_calls'])} calls · ${number(context, model['estimated_cost'], money: true)}',
                                ),
                                if (valid(model['estimated_cost']) &&
                                    total > 0 &&
                                    total.isFinite) ...[
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value:
                                        ((model['estimated_cost'] as num) /
                                                total)
                                            .clamp(0, 1)
                                            .toDouble(),
                                    semanticsLabel:
                                        '${model['model']} share of reported estimated cost',
                                    semanticsValue:
                                        '${((model['estimated_cost'] as num) / total * 100).toStringAsFixed(1)}%',
                                  ),
                                ],
                              ],
                            ),
                          ),
                          children: [
                            for (final (key, label) in [
                              ('sessions', 'Sessions'),
                              ('api_calls', 'Calls'),
                              ('input_tokens', 'Input tokens'),
                              ('output_tokens', 'Output tokens'),
                              ('estimated_cost', 'Estimated cost'),
                            ])
                              ListTile(
                                dense: true,
                                title: Text(label),
                                subtitle: Text(
                                  number(
                                    context,
                                    model[key],
                                    money: key == 'estimated_cost',
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: refresh,
                      child: const Text('Refresh'),
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
